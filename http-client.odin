package http_client

import "./curl"
import "base:runtime"
import "core:c"
import "core:log"
import "core:mem"
import vmem "core:mem/virtual"
import "core:strings"

Curl_handle :: distinct rawptr

Http_Headers :: map[string][]string

Method :: enum {
	GET,
	POST,
	PUT,
	DELETE,
}

Http_Chunk :: struct {
	ctx:         runtime.Context,
	response:    string,
	headers_raw: string,
	headers:     Http_Headers,
}

Http_Response :: struct {
	code:    int,
	headers: Http_Headers,
	body:    string,
	chunk:   ^Http_Chunk,
	client:  ^Http_Client,
}

Http_Client :: struct {
	curl_handle: Curl_handle,
	url:         string,
	headers:     Http_Headers,
	method:      Method,
	body:        string,
	arena:       vmem.Arena,
	allocator:   mem.Allocator,
	response:    ^Http_Response,
}

@(private)
default_body_cb :: proc "c" (
	data: [^]u8,
	size: c.size_t,
	nmemb: c.size_t,
	chunk_ptr: rawptr,
) -> c.size_t {
	chunk: ^Http_Chunk = (^Http_Chunk)(chunk_ptr)
	context = chunk.ctx
	real_size := size * nmemb

	str := strings.clone_from_ptr(data, int(real_size))

	if len(chunk.response) < 1 {
		chunk.response = str
	} else {
		response, err := strings.concatenate({chunk.response, str})
		chunk.response = response
	}

	return size * nmemb
}

@(private)
default_header_write_cb :: proc "c" (
	buffer: [^]u8,
	size: c.size_t,
	nitems: c.size_t,
	chunk_ptr: rawptr,
) -> c.size_t {
	chunk: ^Http_Chunk = (^Http_Chunk)(chunk_ptr)
	context = chunk.ctx
	real_size := size * nitems

	str := strings.clone_from_ptr(buffer, int(real_size))
	if len(chunk.headers_raw) < 1 {
		chunk.headers_raw = str
	} else {
		h, err := strings.concatenate({chunk.headers_raw, str})
		if err != nil {
			log.fatalf("Error allocating for string concatenation in header function: %v", err)
			return 0
		}
		chunk.headers_raw = h
	}

	str = strings.trim_suffix(str, "\r\n")
	split, err := strings.split_n(str, ":", 2)

	if err != nil {
		log.fatalf("Error splitting header: %v", err)
		return 0
	}

	if len(split) < 2 {
		return size * nitems
	}

	key := strings.trim_space(split[0])
	values := split[1]
	values_split := strings.split(values, ";")

	for &v in values_split {
		v = strings.trim_space(v)
	}
	chunk.headers[key] = values_split

	return size * nitems
}

client_run :: proc(client: ^Http_Client) -> Curl_Code {
	context.allocator = client.allocator
	to_cstr := strings.clone_to_cstring

	curl.global_init(curl.GLOBAL_ALL)

	chunk, alloc_err := new(Http_Chunk, client.allocator)
	chunk^ = {
		headers = make(Http_Headers),
		ctx     = context,
	}
	log.debug("Instantiated Chunk")

	slist: ^curl.slist
	log.debug("Curl slist created")

	defer {
		curl.slist_free_all(slist)
	}

	if client.headers != nil {
		defer log.debug("Copied headers to client")
		for key, value in client.headers {
			value_str := strings.join(value[:], ",", allocator = client.allocator)
			str := strings.concatenate({key, ":", value_str}, allocator = client.allocator)
			slist = curl.slist_append(slist, to_cstr(str))
		}
		curl.easy_setopt(client.curl_handle, curl.OPT_HTTPHEADER, slist)
	}

	curl.easy_setopt(client.curl_handle, curl.OPT_HEADER, 0)

	curl.easy_setopt(client.curl_handle, curl.OPT_URL, to_cstr(client.url))
	curl.easy_setopt(client.curl_handle, curl.OPT_URL, to_cstr(client.url))
	curl.easy_setopt(client.curl_handle, curl.OPT_WRITEFUNCTION, default_body_cb)
	curl.easy_setopt(client.curl_handle, curl.OPT_HEADERFUNCTION, default_header_write_cb)
	curl.easy_setopt(client.curl_handle, curl.OPT_WRITEDATA, chunk)
	curl.easy_setopt(client.curl_handle, curl.OPT_HEADERDATA, chunk)
	curl.easy_setopt(client.curl_handle, curl.OPT_SSL_OPTIONS, curl.SSLOPT_NATIVE_CA)

	switch client.method {
	case .GET:
		curl.easy_setopt(client.curl_handle, curl.OPT_HTTPGET, 1)
	case .POST:
		curl.easy_setopt(client.curl_handle, curl.OPT_HTTPPOST, 1)
		curl.easy_setopt(
			client.curl_handle,
			curl.OPT_POSTFIELDS,
			strings.clone_to_cstring(client.body),
		)
	case .PUT:
		curl.easy_setopt(client.curl_handle, curl.OPT_CUSTOMREQUEST, cstring("PUT"))
	case .DELETE:
		curl.easy_setopt(client.curl_handle, curl.OPT_CUSTOMREQUEST, cstring("DELETE"))
	}
	log.debug("Set Curl Options")

	res_code := curl.easy_perform(client.curl_handle)
	log.debug("Performed Curl Call")
	if res_code != curl.E_OK {
		log.fatalf("ERROR WITH CURL %s", curl.easy_strerror(res_code))
		return (Curl_Code)(res_code)
	}

	res := new(Http_Response, allocator = client.allocator)
	log.debug("Allocated Response")

	if res_code == curl.E_OK {
		status: c.long
		curl.easy_getinfo(client.curl_handle, curl.INFO_RESPONSE_CODE, &status)
		res.code = int(status)
	}
	res.body = chunk.response
	res.headers = chunk.headers
	res.chunk = chunk

	client.response = res
	res.client = client

	log.debug("Response mapped")
	return (Curl_Code)(res_code)
}

client_init_none :: proc(client: ^Http_Client) -> mem.Allocator_Error {
	arena: vmem.Arena
	err := vmem.arena_init_growing(&arena)
	if err != nil {
		return err
	}
	cu := (Curl_handle)(curl.easy_init())
	client^ = {
		curl_handle = cu,
		arena       = arena,
	}
	alloc := vmem.arena_allocator(&client.arena)
	client.allocator = alloc

	return nil
}

client_init_url :: proc(client: ^Http_Client, url: string) -> (err: mem.Allocator_Error) {
	client_init_none(client) or_return
	client.url = url
	return
}

client_init_url_and_method :: proc(
	client: ^Http_Client,
	url: string,
	method: Method,
) -> (
	err: mem.Allocator_Error,
) {
	client_init_url(client, url) or_return
	client.method = method
	return
}

client_init :: proc {
	client_init_none,
	client_init_url,
	client_init_url_and_method,
}

client_free :: proc(client: ^Http_Client) {
	curl.easy_cleanup(client.curl_handle)
	vmem.arena_destroy(&client.arena)
	free(client)
	log.debug("Client Freed")
}

response_free :: proc(response: ^Http_Response) {
	client_free(response.client)
}

http_get :: proc(
	path: string,
	headers: Http_Headers = nil,
	allocator := context.allocator,
) -> (
	^Http_Response,
	Curl_Code,
) {
	client := new(Http_Client)
	err := client_init(client)
	if err != nil {
		log.fatalf("Could not init client: %v", err)
	}

	client.url = path
	client.method = .GET
	client.headers = headers

	code := client_run(client)
	return client.response, code
}

http_post :: proc(
	path: string,
	body: string,
	headers: Http_Headers = nil,
	allocator := context.allocator,
) -> (
	^Http_Response,
	Curl_Code,
) {
	client := new(Http_Client)
	err := client_init(client)
	if err != nil {
		log.fatalf("Could not init client: %v", err)
	}

	client.headers = headers
	client.method = .POST
	client.body = body
	client.url = path

	code := client_run(client)
	return client.response, code
}

http_post_json :: proc(
	path: string,
	body: string,
	headers: Http_Headers = nil,
	allocator := context.allocator,
) -> (
	^Http_Response,
	Curl_Code,
) {

	client := new(Http_Client)
	err := client_init(client)
	if err != nil {
		log.fatalf("Could not init client: %v", err)
	}
	new_headers := headers
	if new_headers == nil {
		new_headers = make(map[string][]string, client.allocator)
	}
	new_headers["Content-Type"] = {"application/json"}

	client.headers = new_headers
	client.method = .POST
	client.body = body
	client.url = path

	code := client_run(client)
	return client.response, code
}
