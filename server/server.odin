package main

import "core:container/queue"
import "core:crypto"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:net"
import "core:strings"

import "../mmonet"

server: mmonet.Server = mmonet.create_server(cast(u16)2000)
packet: mmonet.Packet = {}

main :: proc() {

	ex := "Welcome to the Odin UDP Game Server!!! [ Hopefully we'll have TCP implemented soon :) ]"
	fmt.println(ex)
	defer (net.close(server.udp_socket))
	fmt.println(server)

	condition := true
	bytes_read: int
	endpoint: net.Endpoint
	rec_error: net.Network_Error

	id_count: int = 10000

	for condition {

		err_res: net.Network_Error
		packet, err_res, endpoint = mmonet.listen_for_packets(server.udp_socket)

		exists, client := mmonet.check_connection_exists(server.connections, endpoint)

		if queue.len(server.connections) >= cast(int)server.connection_limit &&
		   packet.type == .Connection_Attempt {
			fmt.println("too many connections...")
			continue
		} else if !exists && packet.type == .Connection_Attempt {
			connection := new(mmonet.Connection)
			connection^.endpoint = endpoint
			connection^.client_id = id_count
			connection^.connection_key_original = {}
			connection^.connection_key_to_validate = {}
			queue.push_back(&server.connections, connection)
			id_count = id_count + 1
			client = connection
		}

		// generate the client id code and send back to client?
		switch packet.type {
		case .Connection_Attempt:

			fmt.println("Connection Attempt packet")
			fmt.println("Sending Activation packet...")
			fmt.println(packet)

			key: [20]u8 = {}
			key_to_validate: [20]u8 = {}
			crypto.rand_bytes(key[:])

			fmt.println("Sending Activation packet...")

			client_key := client.connection_key_original

			fmt.println("Sending Activation packet...", client_key)

			count: int = 0
			for &b in client.connection_key_original {
				b = key[count]
				count += 1
			}

			fmt.println("Key original {}", client.connection_key_original)

			mmonet.xor_simple_encrypt(
				client.connection_key_original[:],
				client.connection_key_to_validate[:],
			)

			packet_to_validate: mmonet.Packet = {}
			packet_to_validate.version = mmonet.version
			packet_to_validate.type = .Connection_Attempt_To_Validate

			fmt.println("Key to validate ", client.connection_key_to_validate[:])

			packet_to_validate.data = client.connection_key_to_validate[:]
			packet_to_validate.size = cast(u8)len(packet_to_validate.data)

			mmonet.send_packet(server.udp_socket, packet_to_validate, client.endpoint)

			break

		case .Connection_Attempt_To_Validate:

			data_str: string = transmute(string)packet.data
			data_key: string = transmute(string)client.connection_key_original[:]
			message: string = "Connection success!"
			packet_new: mmonet.Packet = {}

			packet_new.version = mmonet.version
			packet_new.type = mmonet.Packet_Type.Connection_Success
			packet_new.size = cast(u8)len(message)
			packet_new.data = transmute([]u8)message

			if strings.compare(data_key, data_str) == 0 {
				fmt.println("connection validated, sending Connection Success packet")
				mmonet.send_packet(server.udp_socket, packet_new, client.endpoint)
			}
			// do nothing or send failed to validate if the check fails

			break

		case .Info:
			// sending back info about the client connected
			fmt.println("Info packet?")

			sb: strings.Builder
			message: string = "your client id: "
			strings.write_string(&sb, message)
			strings.write_int(&sb, client.client_id)

			packet_new: mmonet.Packet = {}
			packet_new.version = mmonet.version
			packet_new.type = .Info
			packet_new.size = cast(u8)len(sb.buf)
			packet_new.data = sb.buf[:]

			mmonet.send_packet(server.udp_socket, packet_new, client.endpoint)

			break

		case .Not_A_Packet:
			// Do nothing
			// Probably will never hit
			fmt.println("Do nothing, not a packet from an existing client.")

			break
		case .Connection_Success:
			data_str: string = transmute(string)packet.data
			fmt.println(data_str)
			fmt.println("Connection test... ")

			break

		case .Connection_Validated:
			break
		}

	}
}
