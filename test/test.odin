package test

import http_client "../"
import "core:encoding/json"
import "core:log"
import "core:testing"

URL: string = "ENTER URL HERE"

@(test)
test_get :: proc(t: ^testing.T) {
	defer free_all(context.allocator)

	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	response, code := http_client.http_get(URL)
	defer http_client.client_free(response.client)
	if code != .E_OK {
		log.error("Curl Response Not OK")
		testing.fail(t)
	}

	is_ok := response.code == 200
	testing.expect(t, is_ok, "Response was not 200")
}

@(test)
test_post :: proc(t: ^testing.T) {
	defer free_all(context.allocator)

	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	test_data: map[string]string
	test_data["Hello"] = "World"
	data, _ := json.marshal(test_data)

	headers: http_client.Http_Headers
	headers["Content-Type"] = {"application/json"}

	response, code := http_client.http_post(URL, string(data), headers)
	if code != .E_OK {
		log.error("Curl Response Not OK")
		testing.fail(t)
	}

	is_ok := response.code == 200
	testing.expect(t, is_ok, "Response was not 200")

	http_client.client_free(response.client)
	response, code = http_client.http_post_json(URL, string(data))
	defer http_client.response_free(response)
	if code != .E_OK {
		log.error("Curl Response Not OK")
		testing.fail(t)
	}

	is_ok = response.code == 200
	testing.expect(t, is_ok, "Response was not 200")
}

@(test)
test_client :: proc(t: ^testing.T) {
	defer free_all(context.allocator)
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	test_data: map[string]string
	test_data["Hello"] = "World"
	data, _ := json.marshal(test_data)

	client: http_client.Http_Client
	defer http_client.client_free(&client)
	err := http_client.client_init(&client, URL)
	testing.expect(t, err == nil, "Error creating client")

	client.method = .POST
	client.body = string(data)
	client.headers["Content-Type"] = {"application/json"}

	code := http_client.client_run(&client)
	testing.expect(t, code == .E_OK, "Error in curl message")

	testing.expect(t, client.response.code == 200, "Client response was not 200")
}

@(test)
custom_allocator :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	client: http_client.Http_Client
	err := http_client.client_init(&client, URL, context.temp_allocator)
	testing.expect(t, err == nil, "Error initialising client")
	defer {
		http_client.client_free(&client)
		log.destroy_console_logger(context.logger)
		free_all(context.temp_allocator)
	}

	code := http_client.client_run(&client)
	testing.expect(t, code == .E_OK, "Error in curl message")

	testing.expect(t, client.response.code == 200, "Client response was not 200")
}
