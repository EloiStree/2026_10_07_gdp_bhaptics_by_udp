extends Node

var udp := PacketPeerUDP.new()

const BHAPTICS_IP := "127.0.0.1"
const BHAPTICS_PORT := 9100


func _ready():
    udp.connect_to_host(BHAPTICS_IP, BHAPTICS_PORT)


func vest(motor: int, intensity: float, duration_ms: int):
    intensity = clamp(intensity, 0.0, 1.0)
    duration_ms = clamp(duration_ms, 1, 5000)

    var message := "/bhaptics/dot/Vest/%d[%f, %d]" % [
        motor,
        intensity,
        duration_ms
    ]

    udp.put_packet(message.to_utf8_buffer())
