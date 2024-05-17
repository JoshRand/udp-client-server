package main

import "core:container/queue"
import "core:fmt"
import "core:net"
import "core:time"

import "../mmonet"

client: mmonet.Client = mmonet.create_client({})
packet: mmonet.Packet

main :: proc() {

	ex := "Welcome to the Odin UDP game client!!!"
	fmt.println(ex)

	condition := true
	connected := false

	// Not really used, but we're sending this because we can :P
	connection_string: string = "This is some connection data..."

	data: []u8 = {}
	data = transmute([]u8)connection_string

	base_sending_packet: mmonet.Packet = {
		mmonet.version,
		.Connection_Attempt,
		cast(u8)len(data),
		data,
	}

	for condition {

		err_res: net.Network_Error
		endpoint: net.Endpoint
		fmt.println("Sending...")
		mmonet.send_packet(client.udp_socket, base_sending_packet, client.endpoint)
		time.sleep(2 * time.Second)

		for condition {

			if connected {
				time.sleep(2 * time.Second)
				base_sending_packet = {mmonet.version, .Info, 0, {}}
				mmonet.send_packet(client.udp_socket, base_sending_packet, client.endpoint)
			}

			packet, err_res, endpoint = mmonet.listen_for_packets(client.udp_socket)

			#partial switch packet.type {
			case .Connection_Attempt_To_Validate:
				packet_data_to_encrypt := packet.data[:]
				packet_data_dest: [20]u8
				mmonet.xor_simple_encrypt(packet_data_to_encrypt[:], packet_data_dest[:])
				packet_to_validate: mmonet.Packet = {}
				packet_to_validate.version = mmonet.version

				packet_to_validate.type = .Connection_Attempt_To_Validate

				fmt.println(
					"Sending connection attempt to validate packed data... ",
					packet.data[:],
				)

				count: int = 0
				packet_to_validate.data = packet_data_dest[:]
				packet_to_validate.size = cast(u8)len(packet.data)

				fmt.println(
					"Sending connection attempt to validate packed data... ",
					packet_to_validate.data[:],
				)

				mmonet.print_packet(packet_to_validate)
				packet_data: []u8 = packet_to_validate.data

				mmonet.send_packet_test(
					client.udp_socket,
					packet_to_validate,
					packet_data,
					client.endpoint,
				)

				break

			case .Info:
				fmt.println("Info packet?")
				mmonet.print_packet(packet)

				break

			case .Not_A_Packet:
				// Do nothing
				// Probably will never hit
				fmt.println("Do nothing, not a packet from an existing client.")

				break

			case .Connection_Success:
				fmt.println("HEYYYYYYYYYY, WE DID IT!!! :O")
				data_str: string = transmute(string)packet.data
				fmt.println(data_str)
				connected = true

				break

			}
		}
	}
	fmt.println("Broke out!")
}
