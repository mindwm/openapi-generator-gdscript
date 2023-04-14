extends RefCounted
class_name DemoApiBee

# Base class for all generated API endpoints.
#
# Every property/method defined here may collide with userland,
# so these are all listed and excluded in our CodeGen Java file.
# We want to keep the amount of renaming to a minimum, though.
# Therefore, we use the _bzz_ prefix, even if awkward.


const BEE_CONTENT_TYPE_TEXT := "text/plain"
const BEE_CONTENT_TYPE_HTML := "text/html"
const BEE_CONTENT_TYPE_JSON := "application/json"
const BEE_CONTENT_TYPE_FORM := "application/x-www-form-urlencoded"
const BEE_CONTENT_TYPE_JSONLD := "application/json+ld"  # unsupported (for now)
const BEE_CONTENT_TYPE_XML := "application/xml"  # unsupported (for now)

# From this client's point of view.
# Adding a content type here won't magically make the client support it, but you may reorder.
# These are sorted by decreasing preference. (first → preferred)
const BEE_PRODUCIBLE_CONTENT_TYPES := [
	BEE_CONTENT_TYPE_JSON,
	BEE_CONTENT_TYPE_FORM,
]

# From this client's point of view.
# Adding a content type here won't magically make the client support it, but you may reorder.
# These are sorted by decreasing preference. (first → preferred)
const BEE_CONSUMABLE_CONTENT_TYPES := [
	BEE_CONTENT_TYPE_JSON,
]


# Godot's HTTP Client this Api instance is using.
# If none was set (by you), we'll lazily make one.
var _bzz_client: HTTPClient:
	set(value):
		_bzz_client = value
	get:
		if not _bzz_client:
			_bzz_client = HTTPClient.new()
		return _bzz_client


# General configuration that can be shared across Api instances for convenience.
# If no configuration was provided, we'll lazily make one with defaults,
# but you probably want to make your own with your own domain and scheme.
var _bzz_config: DemoApiConfig:
	set(value):
		_bzz_config = value
	get:
		if not _bzz_config:
			_bzz_config = DemoApiConfig.new()
		return _bzz_config


var _bzz_name: String:
	get:
		return _bzz_get_api_name()


# Constructor, where you probably want to inject your configuration,
# and as Godot recommends re-using HTTP clients, your client as well.
func _init(config : DemoApiConfig = null, client : HTTPClient = null):
	if config != null:
		self._bzz_config = config
	if client != null:
		self._bzz_client = client


func _bzz_get_api_name() -> String:
	return "ApiBee"


func _bzz_next_loop_iteration():
	# I can't find `idle_frame` in 4.0, but we probably want idle_frame here
	return Engine.get_main_loop().process_frame


func _bzz_connect_client_if_needed(
	on_success: Callable,  # func()
	on_failure: Callable,  # func(error: DemoApiError)
	#finally: Callable,
):
	if (
		self._bzz_client.get_status() == HTTPClient.STATUS_CONNECTED
		or
		self._bzz_client.get_status() == HTTPClient.STATUS_RESOLVING
		or
		self._bzz_client.get_status() == HTTPClient.STATUS_CONNECTING
		or
		self._bzz_client.get_status() == HTTPClient.STATUS_REQUESTING
		or
		self._bzz_client.get_status() == HTTPClient.STATUS_BODY
	):
		on_success.call()

	var connecting := self._bzz_client.connect_to_host(
		self._bzz_config.host, self._bzz_config.port, self._bzz_config.tls_options
	)
	if connecting != OK:
		var error := DemoApiError.new()
		error.internal_code = connecting
		error.identifier = "apibee.connect_to_host.failure"
		error.message = "%s: failed to connect to `%s' port `%d' with error: %s" % [
			_bzz_name, self._bzz_config.host, self._bzz_config.port,
			_bzz_httpclient_status_string(connecting),
		]
		on_failure.call(error)
		return

	# Wait until resolved and connected.
	while (
		self._bzz_client.get_status() == HTTPClient.STATUS_CONNECTING
		or
		self._bzz_client.get_status() == HTTPClient.STATUS_RESOLVING
	):
		self._bzz_client.poll()
		self._bzz_config.log_debug("Connecting…")
		if self._bzz_config.polling_interval_ms:
			OS.delay_msec(self._bzz_config.polling_interval_ms)
		await _bzz_next_loop_iteration()

	var connected := self._bzz_client.get_status()
	if connected != HTTPClient.STATUS_CONNECTED:
		var error := DemoApiError.new()
		error.internal_code = connected as Error
		error.identifier = "apibee.connect_to_host.wrong_status"
		error.message = "%s: failed to connect to `%s' port `%d' : %s" % [
			_bzz_name, self._bzz_config.host, self._bzz_config.port,
			_bzz_httpclient_status_string(connected),
		]
		on_failure.call(error)
		return

	on_success.call()


func bzz_request(
	method: int,  # one of HTTPClient.METHOD_XXXXX
	path: String,
	headers: Dictionary,
	query: Dictionary,
	body,  # Variant that will be serialized and sent
	on_success: Callable,  # func(response: Variant, responseCode: int, responseHeaders: Dictionary)
	on_failure: Callable,  # func(error: DemoApiError)
):
	# This method does not handle full deserialization, it only handles decode and not denormalization.
	# Denormalization is handled in each generated API endpoint in the on_success callable of this method.
	# This is because this method already has plethora of parameters and we don't want even more.

	_bzz_request_text(
		method, path, headers, query, body,
		func(responseText, responseCode, responseHeaders):
			var mime: String = responseHeaders['Mime']
			var decodedResponse  # Variant

			if BEE_CONTENT_TYPE_TEXT == mime:
				decodedResponse = responseText
			elif BEE_CONTENT_TYPE_HTML == mime:
				decodedResponse = responseText
			elif BEE_CONTENT_TYPE_JSON == mime:
				var parser := JSON.new()
				var parsing := parser.parse(responseText)
				if OK != parsing:
					var error := DemoApiError.new()
					error.internal_code = parsing
					error.identifier = "apibee.decode.cannot_parse_json"
					error.message = "%s: failed to parse JSON response at line %d.\n%s" % [
						_bzz_name, parser.get_error_line(), parser.get_error_message()
					]
					on_failure.call(error)
					return
				decodedResponse = parser.data
			else:
				var error := DemoApiError.new()
				error.internal_code = ERR_INVALID_DATA
				error.identifier = "apibee.decode.mime_type_unsupported"
				error.message = "%s: mime type `%s' is not supported (yet)" % [
					_bzz_name, mime
				]
				on_failure.call(error)
				return

			on_success.call(decodedResponse, responseCode, responseHeaders)
			,
		func(error):
			on_failure.call(error)
			,
	)


func _bzz_request_text(
	method: int,  # one of HTTPClient.METHOD_XXXXX
	path: String,
	headers: Dictionary,
	query: Dictionary,
	body,  # Variant that will be serialized
	on_success: Callable,  # func(responseText: String, responseCode: int, responseHeaders: Dictionary)
	on_failure: Callable,  # func(error: DemoApiError)
):
	_bzz_connect_client_if_needed(
		func():
			_bzz_do_request_text(method, path, headers, query, body, on_success, on_failure)
			,
		func(error):
			on_failure.call(error)
			,
	)


func _bzz_do_request_text(
	method: int,  # one of HTTPClient.METHOD_XXXXX
	path: String,
	headers: Dictionary,
	query: Dictionary,
	body,  # Variant that will be serialized
	on_success: Callable,  # func(responseText: String, responseCode: int, responseHeaders: Dictionary)
	on_failure: Callable,  # func(error: DemoApiError)
):

	headers = headers.duplicate(true)
	headers.merge(self._bzz_config.headers_base)
	headers.merge(self._bzz_config.headers_override, true)

	var body_normalized = body
	if body is Object:
		if body.has_method('bzz_collect_missing_properties'):
			var missing_properties : Array = body.bzz_collect_missing_properties()
			if missing_properties:
				var error := DemoApiError.new()
				error.identifier = "apibee.request.body.missing_properties"
				error.message = "%s: `%s' is missing required properties %s." % [
					_bzz_name, body.bzz_class_name, missing_properties
				]
				on_failure.call(error)
				return
		if body.has_method('bzz_normalize'):
			body_normalized = body.bzz_normalize()

	var body_serialized := ""
	var content_type := self._bzz_get_content_type(headers)
	if content_type == BEE_CONTENT_TYPE_JSON:
		body_serialized = JSON.stringify(body_normalized)
	elif content_type == BEE_CONTENT_TYPE_FORM:
		body_serialized = self._bzz_client.query_string_from_dict(body_normalized)
	else:
		# TODO: Handle other serialization schemes (json+ld, xml…)
		push_warning("Unsupported content-type `%s`." % content_type)

	var path_queried := path
	var query_string := self._bzz_client.query_string_from_dict(query)
	if query_string:
		path_queried = "%s?%s" % [path, query_string]

	var headers_for_godot := Array()  # of String
	for key in headers:
		headers_for_godot.append("%s: %s" % [key, headers[key]])

	self._bzz_config.log_info("%s: REQUEST %s %s" % [_bzz_name, method, path_queried])
	if not headers.is_empty():
		self._bzz_config.log_debug("→ HEADERS: %s" % [str(headers)])
	if body_serialized:
		self._bzz_config.log_debug("→ BODY: \n%s" % [body_serialized])

	var requesting := self._bzz_client.request(method, path_queried, headers_for_godot, body_serialized)
	if requesting != OK:
		var error := DemoApiError.new()
		error.internal_code = requesting
		error.identifier = "apibee.request.failure"
		error.message = "%s: failed to request to path `%s'." % [
			_bzz_name, path
		]
		on_failure.call(error)
		return

	while self._bzz_client.get_status() == HTTPClient.STATUS_REQUESTING:
		# Keep polling for as long as the request is being processed.
		self._bzz_client.poll()
		self._bzz_config.log_debug("Requesting…")
		if self._bzz_config.polling_interval_ms:
			OS.delay_msec(self._bzz_config.polling_interval_ms)
		await _bzz_next_loop_iteration()

	if not self._bzz_client.has_response():
		var error := DemoApiError.new()
		error.identifier = "apibee.request.no_response"
		error.message = "%s: request to `%s' returned no response whatsoever. (status=%d)" % [
			_bzz_name, path, self._bzz_client.get_status(),
		]
		on_failure.call(error)
		return

	var response_code := self._bzz_client.get_response_code()
	var response_headers := self._bzz_client.get_response_headers_as_dictionary()
	# FIXME: extract from headers "Content-Type": "application/json; charset=utf-8"
	# This begs for a HttpResponse class ; wait for Godot?
	var encoding := "utf-8"
	var mime := "application/json"
	response_headers['Encoding'] = encoding
	response_headers['Mime'] = mime

	# TODO: cap the size of this, perhaps?
	var response_bytes := PackedByteArray()

	while self._bzz_client.get_status() == HTTPClient.STATUS_BODY:
		self._bzz_client.poll()
		var chunk = self._bzz_client.read_response_body_chunk()
		if chunk.size() == 0:  # Got nothing, wait for buffers to fill a bit.
			if self._bzz_config.polling_interval_ms:
				OS.delay_usec(self._bzz_config.polling_interval_ms)
			await _bzz_next_loop_iteration()
		else:  # Yummy data has arrived
			response_bytes = response_bytes + chunk

	self._bzz_config.log_info("%s: RESPONSE %d (%d bytes)" % [
		_bzz_name, response_code, response_bytes.size()
	])
	if not response_headers.is_empty():
		self._bzz_config.log_debug("→ HEADERS: %s" % str(response_headers))

	var response_text: String
	if encoding == "utf-8":
		response_text = response_bytes.get_string_from_utf8()
	elif encoding == "utf-16":
		response_text = response_bytes.get_string_from_utf16()
	elif encoding == "utf-32":
		response_text = response_bytes.get_string_from_utf32()
	else:
		response_text = response_bytes.get_string_from_ascii()

	if response_text:
		self._bzz_config.log_debug("→ BODY: \n%s" % response_text)

	if response_code >= 500:
		var error := DemoApiError.new()
		error.internal_code = ERR_PRINTER_ON_FIRE
		error.response_code = response_code
		error.identifier = "apibee.response.5xx"
		error.message = "%s: request to `%s' made the server hiccup with a %d." % [
			_bzz_name, path, response_code
		]
		error.message += "\n%s" % [
			_bzz_format_error_response(response_text)
		]
		on_failure.call(error)
		return
	elif response_code >= 400:
		var error := DemoApiError.new()
		error.identifier = "apibee.response.4xx"
		error.response_code = response_code
		error.message = "%s: request to `%s' was denied with a %d." % [
			_bzz_name, path, response_code
		]
		error.message += "\n%s" % [
			_bzz_format_error_response(response_text)
		]
		on_failure.call(error)
		return
	elif response_code >= 300:
		var error := DemoApiError.new()
		error.identifier = "apibee.response.3xx"
		error.response_code = response_code
		error.message = "%s: request to `%s' was redirected with a %d.  We do not support redirects in that client yet." % [
			_bzz_name, path, response_code
		]
		on_failure.call(error)
		return

	# Should we close ?
	#self._bzz_client.close()

	on_success.call(response_text, response_code, response_headers)


func _bzz_convert_http_method(method: String) -> int:
	match method:
		'GET': return HTTPClient.METHOD_GET
		'POST': return HTTPClient.METHOD_POST
		'PUT': return HTTPClient.METHOD_PUT
		'PATCH': return HTTPClient.METHOD_PATCH
		'DELETE': return HTTPClient.METHOD_DELETE
		'CONNECT': return HTTPClient.METHOD_CONNECT
		'HEAD': return HTTPClient.METHOD_HEAD
		'MAX': return HTTPClient.METHOD_MAX
		'OPTIONS': return HTTPClient.METHOD_OPTIONS
		'TRACE': return HTTPClient.METHOD_TRACE
		_:
			push_error("%s: unknown http method `%s`, assuming GET." % [
				_bzz_name, method
			])
			return HTTPClient.METHOD_GET


func _bzz_urlize_path_param(anything) -> String:
	var serialized := _bzz_escape_path_param(str(anything))
	return serialized


func _bzz_escape_path_param(value: String) -> String:
	# TODO: escape for URL
	return value


func _bzz_get_content_type(headers: Dictionary) -> String:
	if headers.has("Content-Type"):
		return headers["Content-Type"]
	return BEE_PRODUCIBLE_CONTENT_TYPES[0]


func _bzz_format_error_response(response: String) -> String:
	# TODO: handle other (de)serialization schemes
	var parser := JSON.new()
	var parsing := parser.parse(response)
	if OK != parsing:
		return response
	if not (parser.data is Dictionary):
		return response
	var s := "ERROR"
	if parser.data.has("code"):
		s += " %d" % parser.data['code']
	if parser.data.has("message"):
		s += "\n%s" % parser.data['message']
	else:
		return response
	return s


func _bzz_httpclient_status_info(status: int) -> Dictionary:
	# At some point Godot ought to natively implement this and we won't need this "shim" anymore.
	match status:
		HTTPClient.STATUS_DISCONNECTED: return {
			"name": "STATUS_DISCONNECTED",
			"description": "Disconnected from the server."
		}
		HTTPClient.STATUS_RESOLVING: return {
			"name": "STATUS_RESOLVING",
			"description": "Currently resolving the hostname for the given URL into an IP."
		}
		HTTPClient.STATUS_CANT_RESOLVE: return {
			"name": "STATUS_CANT_RESOLVE",
			"description": "DNS failure: Can't resolve the hostname for the given URL."
		}
		HTTPClient.STATUS_CONNECTING: return {
			"name": "STATUS_CONNECTING",
			"description": "Currently connecting to server."
		}
		HTTPClient.STATUS_CANT_CONNECT: return {
			"name": "STATUS_CANT_CONNECT",
			"description": "Can't connect to the server."
		}
		HTTPClient.STATUS_CONNECTED: return {
			"name": "STATUS_CONNECTED",
			"description": "Connection established."
		}
		HTTPClient.STATUS_REQUESTING: return {
			"name": "STATUS_REQUESTING",
			"description": "Currently sending request."
		}
		HTTPClient.STATUS_BODY: return {
			"name": "STATUS_BODY",
			"description": "HTTP body received."
		}
		HTTPClient.STATUS_CONNECTION_ERROR: return {
			"name": "STATUS_CONNECTION_ERROR",
			"description": "Error in HTTP connection."
		}
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR: return {
			"name": "STATUS_TLS_HANDSHAKE_ERROR",
			"description": "Error in TLS handshake."
		}
	return {
		"name": "UNKNOWN (%d)" % status,
		"description": "Unknown HTTPClient status."
	}


func _bzz_httpclient_status_string(status: int) -> String:
	var info := _bzz_httpclient_status_info(status)
	return "%s (%s)" % [info["description"], info["name"]]

