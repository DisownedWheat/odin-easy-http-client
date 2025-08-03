# HTTP-Client

A very basic wrapper around libcurl that works on Linux and Windows (and maybe macos).

## Usage

- For Linux users ensure `libcurl` is installed on your system.
- For Windows users you have two options:
  - Use your system install of `libcurl-x64.dll`
  - Copy/move the included `libcurl-x64.dll` alongside the compiled output of your program.

## Examples

### Using the simple interface

#### GET

```Odin
import "core:fmt"
import http "http-client"

main :: proc() {
	url := "https://odin-lang.org/"

	response, code := http.http_get(url)
	defer http.response_free(response)

	if code != .E_OK {
		fmt.panicf("Curl error: %s", http.curl_strerror(code))
	}

	fmt.println(response)
}
```

#### POST With JSON

```Odin
import "core:encoding/json"
import "core:fmt"
import http "http-client"

Payload :: struct {
	value:   int,
	message: string,
}

main :: proc() {
	url := "https://example.com"

	data := Payload {
		value   = 1,
		message = "Payload message",
	}

	msg, _ := json.marshal(data)

	response, code := http.http_post_json(url, string(msg))
	defer http.response_free(response)

	if code != .E_OK {
		fmt.panicf("Curl error: %s", http.curl_strerror(code))
	}

	fmt.println(response)
}
```

### Using Http_Client

```Odin
import "core:encoding/json"
import "core:fmt"
import http "http-client"

Payload :: struct {
	value:   int,
	message: string,
}

main :: proc() {
	url := "https://example.com"

	data := Payload {
		value   = 1,
		message = "Payload message",
	}

	msg, _ := json.marshal(data)

	client: http.Http_Client
	defer http.client_free(&client)
	err := http.client_init(&client, url)
	if err != nil {
		fmt.panicf("Error initialising Http_Client: %v", err)
	}

	client.method = .POST
	client.body = string(msg)
	client.headers["Content-Type"] = {"application/json"}

	code := http.client_run(&client)

	if code != .E_OK {
		fmt.panicf("Curl error: %s", http.curl_strerror(code))
	}

	fmt.println(client.response)
}
```
