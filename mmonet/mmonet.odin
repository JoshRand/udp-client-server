package mmonet

import "core:container/queue"
import "core:crypto"
import "core:fmt"
import "core:mem"
import "core:net"
import "core:strings"

// secrets
version: u8 = 0x23
// maybe we can load these from an .env?
a_key: string = "DEADBEEFC0DECAFE"
b_key: string = "SERVER_2024"


Packet_Type :: enum {
	Not_A_Packet,
	Info,
	Connection_Attempt = 22,
	Connection_Success,
	Connection_Attempt_To_Validate,
	Connection_Validated,
}

Server :: struct {
	connections:           queue.Queue(^Connection),
	validated_connections: queue.Queue(^Connection),
	packet_queue:          queue.Queue(^Packet),
	// server net
	udp_socket:            net.UDP_Socket,
	endpoint:              net.Endpoint,
	connection_limit:      u16,
}

create_server :: proc(limit: u16) -> Server {

	fmt.println("Starting server")
	fmt.println("Initializing connections queue..")
	connections: queue.Queue(^Connection)
	validated_connections: queue.Queue(^Connection)
	packet_queue: queue.Queue(^Packet)
	fmt.println(connections.len)

	// Start the Udp and Tcp servers on localhost
	address: net.Address = net.IP4_Loopback
	port: int = 7777
	udp_socket: net.UDP_Socket
	err: net.Network_Error
	udp_socket, err = net.make_bound_udp_socket(address, port)
	assert(err == nil)

	return {connections, validated_connections, packet_queue, udp_socket, {address, port}, limit}

}

Client :: struct {
	udp_socket:   net.UDP_Socket,
	endpoint:     net.Endpoint,
	packet_queue: queue.Queue(^Packet),
}

create_client :: proc(endpoint: net.Endpoint) -> Client {

	fmt.println("Starting client")
	// Start the Udp and Tcp servers on localhost
	address: net.Address = net.IP4_Loopback
	port: int = 7777

	if endpoint.port != 0 {
		address = endpoint.address
		port = endpoint.port
	}

	packet_queue: queue.Queue(^Packet)
	udp_socket: net.UDP_Socket
	err: net.Network_Error
	udp_socket, err = net.make_bound_udp_socket(address, port)
	endpoint: net.Endpoint = {address, port}

	return {udp_socket, endpoint, packet_queue}
}

// Connection for UDP endpoint..
Connection :: struct {
	endpoint:                   net.Endpoint,
	client_id:                  int,
	allowed_connection:         bool,
	connection_key_original:    [20]u8,
	connection_key_to_validate: [20]u8,
	// String? returned by the client to validate connection principles
}

Packet :: struct {
	//header
	version: u8,
	type:    Packet_Type,
	size:    u8,
	//data
	data:    []u8,
}

print_packet :: proc(packet: Packet) {

	fmt.println("Packet Version: ", packet.version)
	fmt.println("Packet Type: ", packet.type)
	fmt.println("Packet Size: ", packet.size)
	fmt.println("Packet Data: ", packet.data)
	data_str: string = transmute(string)packet.data
	fmt.println("Packet data String: ", data_str)

}

Connection_Approved :: struct {
	status: bool,
}

send_packet_test :: proc(
	udp_socket: net.UDP_Socket,
	packet: Packet,
	data: []u8,
	endpoint: net.Endpoint,
) {

	print_packet(packet)
	fmt.println("sending... packet size ", packet.size)
	fmt.println("sending... packet ", data)

	pack_data: []u8 = encrypt_packet(packet)
	net.send_any(udp_socket, pack_data, endpoint)
	fmt.println("sending end... ")

}

send_packet :: proc(udp_socket: net.UDP_Socket, packet: Packet, endpoint: net.Endpoint) {

	packet := packet

	fmt.println("sending... packet size ", packet.size)
	fmt.println("sending... packet ", packet.data)

	data: []u8 = encrypt_packet(packet)
	encrypted_packet: []u8 = data[0:packet.size + 3]

	net.send_any(udp_socket, encrypted_packet, endpoint)
	fmt.println("sending end... ")
}

encrypt_packet :: proc(packet: Packet) -> []u8 {

	packet_data: [dynamic]u8
	append(&packet_data, packet.version)
	append(&packet_data, cast(u8)packet.type)
	append(&packet_data, packet.size)

	packet_data_to_copy: []u8 = packet.data
	for i in 3 ..< packet.size + 3 {
		append(&packet_data, packet_data_to_copy[i - 3])
	}

	fmt.println("packet before encrypt data")

	for i in 0 ..< len(packet.data) + 3 {
		for a in 0 ..< len(a_key) {
			packet_data[i] = packet_data[i] ~ a_key[a]
		}
	}

	return packet_data[:]
}

decrypt_packet :: proc(packet_to_decrypt: [1024]u8) -> Packet {

	packet_data: [1024]u8
	packet_data = packet_to_decrypt
	packet: Packet

	for i in 0 ..< len(packet_data) {
		for a in 0 ..< len(a_key) {
			packet_data[i] = packet_data[i] ~ a_key[a]
		}
		// checking the version
		if i == 0 && packet_data[0] == version {
			// packing the version
			packet.version = packet_data[i]
		} else if i == 0 && packet_data[0] != version {
			fmt.println("Incorrect packet verison")
			return Packet{0, .Not_A_Packet, 0, nil}
		}
	}

	packet.version = packet_data[0]
	packet.type = cast(Packet_Type)packet_data[1]
	packet.size = packet_data[2]

	if packet.size != 0 {
		packet.data = packet_data[3:3 + packet.size]
	}

	return packet
}

listen_for_packets :: proc(
	udp_socket: net.UDP_Socket,
) -> (
	packet_res: Packet,
	err_res: net.Network_Error,
	endpoint_res: net.Endpoint,
) {

	buff: [1024]u8
	err: net.Network_Error
	endpoint: net.Endpoint
	bytes_read: int
	bytes_read, endpoint, err = net.recv_udp(udp_socket, buff[:])

	if len(buff) == 0 {
		return Packet{version, .Not_A_Packet, 0, nil}, err, endpoint
	}

	return decrypt_packet(buff), err, endpoint
}

check_connection_exists :: proc(
	connections: queue.Queue(^Connection),
	new_endpoint: net.Endpoint,
) -> (
	condition: bool,
	connection: ^Connection,
) {
	// Checking to see if there is an existing connection
	for i in 0 ..< connections.len {
		connection := connections.data[i]

		if connection.endpoint.address == new_endpoint.address &&
		   connection.endpoint.port == new_endpoint.port {
			return true, connection
		}
	}

	return false, nil
}

xor_simple_encrypt :: proc(data: []u8, dst: []u8) {
    // just a simple xor encrypt for client validation
	for i in 0 ..< len(data) {
		for a in 0 ..< len(b_key) {
			dst[i] = data[i] ~ b_key[a]
		}
	}
}
