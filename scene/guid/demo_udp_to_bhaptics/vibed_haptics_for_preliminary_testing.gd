class_name BHOscVest
extends Node
## ------------------------------------------------------------------
##  OSC driver for bHaptics vests (TactSuit) over UDP.
##
##  Fixes / upgrades over the naive version:
##   1. CORRECT float encoding — OSC floats are big-endian IEEE-754
##      singles. var_to_bytes() wrote Variant bytes (garbage on receive).
##   2. Rate-limited send queue — bHaptics Player drops packets when
##      flooded; bursts are smoothed to max_send_rate_hz.
##   3. Optional OSC bundles — many messages packed into one datagram.
##   4. stop_all() also flushes the queue (no stale pulses afterwards).
##   5. Timer-based test loop (cancels cleanly on exit) + helpers:
##      motors(), pulse() with falloff, async sweep().
## ------------------------------------------------------------------

signal packet_sent(byte_count: int)

const MAX_QUEUE := 128

@export_group("Connection")
@export var bhaptics_ip: String = "127.0.0.1"
@export_range(1, 65535) var bhaptics_port: int = 9100

@export_group("Vest")
@export_range(1, 40) var motor_count: int = 40
## Intensity is 0..1 in the API, multiplied by this when sent.
## Set to 100.0 if your bridge expects percentages.
@export var intensity_max: float = 1.0
@export_range(1, 10000) var max_duration_ms: int = 5000

@export_group("Sending")
@export_range(5.0, 240.0) var max_send_rate_hz: float = 60.0
@export var use_bundles: bool = false   # requires bundle-aware bridge
@export var debug_print: bool = false

@export_group("Testing")
@export var test_mode: bool = true
@export_range(0.05, 5.0) var test_interval_s: float = 0.4

var _udp := PacketPeerUDP.new()
var _buf := StreamPeerBuffer.new()
var _queue: Array[PackedByteArray] = []
var _budget := 0.0
var _test_timer: Timer


func _ready() -> void:
	_buf.big_endian = true

	var err := _udp.connect_to_host(bhaptics_ip, bhaptics_port)
	if err != OK:
		push_error("[BH-OSC] UDP setup failed: %s" % error_string(err))
		set_process(false)
		return
	print("[BH-OSC] target %s:%d — %d motors" % [bhaptics_ip, bhaptics_port, motor_count])

	_test_timer = Timer.new()
	_test_timer.wait_time = test_interval_s
	_test_timer.timeout.connect(_on_test_tick)
	add_child(_test_timer)
	_test_timer.start()

	motor(int(motor_count * 0.5), 0.9, 300)   # hello-pulse


# ---------------------------------------------------------------- public API

## Mapping 1 — single motor: /bhaptics/dot/Vest/{index}  (f intensity, i duration)
func motor(index: int, intensity: float = 1.0, duration_ms: int = 300) -> void:
	index = clampi(index, 0, motor_count - 1)
	enqueue("/bhaptics/dot/Vest/%d" % index,
			[_scaled_intensity(intensity), _clamped_duration(duration_ms)])


## Several motors in one call (one OSC message each).
func motors(indices: Array, intensity: float = 1.0, duration_ms: int = 300) -> void:
	for i in indices:
		motor(i, intensity, duration_ms)


## Radial pulse around `center`, linear falloff over `radius` motors each side.
func pulse(center: int, radius: int, intensity: float = 1.0, duration_ms: int = 300) -> void:
	center = clampi(center, 0, motor_count - 1)
	radius = maxi(radius, 0)
	var lo := maxi(0, center - radius)
	var hi := mini(motor_count - 1, center + radius)
	for i in range(lo, hi + 1):
		var falloff := 1.0 - float(absi(i - center)) / float(radius + 1)
		motor(i, intensity * falloff, duration_ms)


## Async helper: light up motors in order. Call as: `await vest.sweep(...)`
func sweep(indices: Array, intensity: float = 1.0, ms_per_step: int = 80) -> void:
	for i in indices:
		motor(i, intensity, ms_per_step * 2)   # *2 so steps overlap smoothly
		await get_tree().create_timer(ms_per_step / 1000.0).timeout


## Mapping 2 — stop named event: /bhaptics/stop/{event}
func stop_event(event_name: String) -> void:
	enqueue("/bhaptics/stop/" + event_name, [], true)


## Mapping 3 — global stop: /bhaptics/stop   (also flushes pending pulses)
func stop_all() -> void:
	_queue.clear()
	enqueue("/bhaptics/stop", [], true)


## Generic escape hatch — any address, any supported args.
func send(address: String, args: Array = [], immediate: bool = false) -> void:
	enqueue(address, args, immediate)


## Send everything queued right now, ignoring the rate limit.
func flush() -> void:
	while not _queue.is_empty():
		_udp_put(_queue.pop_front())


func set_target(ip: String, port: int) -> void:
	bhaptics_ip = ip
	bhaptics_port = port
	_udp.connect_to_host(ip, port)


# ------------------------------------------------------------ queue / send

func enqueue(address: String, args: Array = [], immediate: bool = false) -> void:
	var packet := _encode_message(address, args)
	if packet.is_empty():
		return
	if immediate:
		_udp_put(packet)
		return
	if _queue.size() >= MAX_QUEUE:
		_queue.pop_front()          # drop oldest — newest input matters most
	_queue.append(packet)


func _process(delta: float) -> void:
	if _queue.is_empty():
		return
	_budget = minf(_budget + delta * max_send_rate_hz, 4.0)
	var burst: Array[PackedByteArray] = []
	while _budget >= 1.0 and not _queue.is_empty():
		_budget -= 1.0
		burst.append(_queue.pop_front())
	if burst.is_empty():
		return
	if use_bundles and burst.size() > 1:
		_udp_put(_encode_bundle(burst))
	else:
		for p in burst:
			_udp_put(p)


func _udp_put(packet: PackedByteArray) -> void:
	var err := _udp.put_packet(packet)
	if err != OK:
		push_warning("[BH-OSC] put_packet failed: %s" % error_string(err))
		return
	packet_sent.emit(packet.size())
	if debug_print:
		print("[BH-OSC] %d bytes → %s:%d" % [packet.size(), bhaptics_ip, bhaptics_port])


# ------------------------------------------------------------ OSC encoding

func _encode_message(address: String, args: Array) -> PackedByteArray:
	if not _address_ok(address):
		return PackedByteArray()
	_buf.clear()
	_buf.big_endian = true

	_put_string(address)

	var tags := ","
	for a in args:
		match typeof(a):
			TYPE_FLOAT:  tags += "f"
			TYPE_INT:    tags += "i"
			TYPE_STRING: tags += "s"
			TYPE_BOOL:   tags += ("T" if a else "F")
			_:
				push_error("[BH-OSC] unsupported argument type: %s" % type_string(typeof(a)))
				return PackedByteArray()
	_put_string(tags)

	for a in args:
		match typeof(a):
			TYPE_FLOAT:
				_buf.put_float(float(a))       # big-endian IEEE-754 single ✓
			TYPE_INT:
				_put_u32(int(a))
			TYPE_STRING:
				_put_string(String(a))
			TYPE_BOOL:
				pass                            # T/F tags carry no payload
	return _buf.data_array


func _encode_bundle(messages: Array[PackedByteArray]) -> PackedByteArray:
	_buf.clear()
	_buf.big_endian = true
	_put_string("#bundle")
	_put_u32(0)
	_put_u32(1)              # timetag = 1 → "immediately" per OSC spec
	for m in messages:
		_put_u32(m.size())
		_buf.put_data(m)
	return _buf.data_array


func _put_string(s: String) -> void:
	var bytes := s.to_utf8_buffer()
	bytes.append(0)                       # null terminator
	while bytes.size() % 4 != 0:
		bytes.append(0)                   # pad to 4-byte boundary
	_buf.put_data(bytes)


func _put_u32(v: int) -> void:
	v &= 0xFFFFFFFF
	_buf.put_u8((v >> 24) & 0xFF)
	_buf.put_u8((v >> 16) & 0xFF)
	_buf.put_u8((v >> 8) & 0xFF)
	_buf.put_u8(v & 0xFF)


func _address_ok(address: String) -> bool:
	if not address.begins_with("/"):
		push_error("[BH-OSC] OSC address must start with '/': %s" % address)
		return false
	if " " in address or "#" in address:
		push_error("[BH-OSC] invalid OSC address: %s" % address)
		return false
	return true


# ------------------------------------------------------------ misc helpers

func _scaled_intensity(i: float) -> float:
	return clampf(i, 0.0, 1.0) * intensity_max


func _clamped_duration(ms: int) -> int:
	return clampi(ms, 1, max_duration_ms)


func _on_test_tick() -> void:
	if not test_mode:
		return
	match randi_range(0, 2):
		0:  # single random motor
			motor(randi_range(0, motor_count - 1), randf_range(0.2, 1.0), randi_range(80, 400))
		1:  # radial burst
			pulse(randi_range(2, motor_count - 3), randi_range(1, 3), 1.0, 350)
		2:  # small random cluster
			motors(_random_set(randi_range(2, 5)), randf_range(0.3, 0.9), 250)


func _random_set(count: int) -> Array:
	var picked := {}
	while picked.size() < mini(count, motor_count):
		picked[randi_range(0, motor_count - 1)] = true
	return picked.keys()


func _exit_tree() -> void:
	stop_all()
	_udp.close()
