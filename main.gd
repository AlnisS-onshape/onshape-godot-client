tool

extends Spatial

const ALPHANUMERIC_CHARACTERS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const HTTP_METHODS = ["GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS", "TRACE", "CONNECT", "PATCH"]

var face_material = preload("res://materials/face_material.material")
var last_mouse_position = Vector2.ZERO
var materials := Dictionary()
var crypto = Crypto.new()

func _ready():
	randomize()
	onshape_request($EdgeHTTPRequest, "https://cad.onshape.com/api/partstudios/d/bd3e28cca10081e0a5ad3ef8/w/f254fe7c4889c85a6841547f/e/f73186e750b795fdac6fbae0/tessellatededges?rollbackBarIndex=-1")
	onshape_request($FaceHTTPRequest, "https://cad.onshape.com/api/partstudios/d/bd3e28cca10081e0a5ad3ef8/w/f254fe7c4889c85a6841547f/e/f73186e750b795fdac6fbae0/tessellatedfaces?rollbackBarIndex=-1&outputFaceAppearances=true&outputVertexNormals=false&outputFacetNormals=true&outputTextureCoordinates=false&outputIndexTable=false&outputErrorFaces=false&combineCompositePartConstituents=false")


func _process(delta):
	if Engine.is_editor_hint():
		return
	
	var mouse_delta = get_viewport().get_mouse_position() - last_mouse_position
	
	if Input.is_action_pressed("rotate"):
		$CameraBase.rotate($CameraBase/Camera.get_global_transform().basis.y, mouse_delta.x * -0.01)
		$CameraBase.rotate($CameraBase/Camera.get_global_transform().basis.x, mouse_delta.y * -0.01)
	
	last_mouse_position = get_viewport().get_mouse_position()


func onshape_request(http_request, url, method = HTTPClient.METHOD_GET,
		request_data = "", content_type = "application/json"):
	var time = OS.get_datetime(true)
	var date = "%s, %02d %s %d %02d:%02d:%02d GMT" % [WEEKDAYS[time.weekday], time.day,
			MONTHS[time.month-1], time.year, time.hour, time.minute, time.second]

	var nonce = '%010d%010d' % [randi(), randi()]
	
	var signature = create_signature(HTTP_METHODS[method], url, nonce, date,
			content_type, Creds.access_key, Creds.secret_key)
	
	var error = http_request.request(url, [
		"Content-Type: " + content_type,
		"Date: " + date,
		"On-Nonce: " + nonce,
		"Authorization: " + signature
	], true, method, request_data)
	
	if error != OK:
		push_error("HTTP request error: %s" % error)

func _face_request_completed(result, response_code, headers, body):
	var response = parse_json(body.get_string_from_utf8())
	generate_faces(response)

func _edge_request_completed(result, response_code, headers, body):
	var response = parse_json(body.get_string_from_utf8())
	generate_edges(response)


func create_signature(method, url, nonce, auth_date, content_type, access_key, secret_key):
	var path_start = url.find('/api/')
	var parameters_start = url.find('?')
	
	var url_path = url.substr(path_start, parameters_start - path_start)
	var url_query = url.substr(parameters_start + 1) if parameters_start != -1 else ''
	
	var combined = ("%s\n%s\n%s\n%s\n%s\n%s\n" % [method, nonce, auth_date,
			content_type, url_path, url_query]).to_lower()
	
	var hmac = Marshalls.raw_to_base64(crypto.hmac_digest(
			HashingContext.HASH_SHA256, secret_key.to_ascii(), combined.to_ascii()))
	
	return 'On %s:HmacSHA256:%s' % [access_key, hmac]

# https://cad.onshape.com/api/partstudios/d/bd3e28cca10081e0a5ad3ef8/w/f254fe7c4889c85a6841547f/e/f73186e750b795fdac6fbae0/tessellatededges?rollbackBarIndex=-1
func generate_edges(edge_json):
	var edge_verts = PoolVector3Array()
	
	for body in edge_json:
		for edge in body.edges:
			var last = null
			for vertex in edge.vertices:
				var next = Vector3(vertex[0], vertex[1], vertex[2]) * 39.3700787
				if last:
					edge_verts.append(last)
					edge_verts.append(next)
				last = next
	
	var arr = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = edge_verts
	
	$Edges.mesh.clear_surfaces()
	$Edges.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)

# https://cad.onshape.com/api/partstudios/d/bd3e28cca10081e0a5ad3ef8/w/f254fe7c4889c85a6841547f/e/f73186e750b795fdac6fbae0/tessellatedfaces?rollbackBarIndex=-1&outputFaceAppearances=true&outputVertexNormals=false&outputFacetNormals=true&outputTextureCoordinates=false&outputIndexTable=false&outputErrorFaces=false&combineCompositePartConstituents=false
func generate_faces(face_json):
	$Faces.mesh.clear_surfaces()
	
	var verts = PoolVector3Array()
	var normals = PoolVector3Array()
	var colors = PoolColorArray()
	
	var face_index = 0
	for body in face_json:
		for face in body.faces:
			
			var color_base64 = body.color
			if "color" in face:
				color_base64 = face.color
			var cd = Marshalls.base64_to_raw(color_base64)
			var color = Color8(cd[0], cd[1], cd[2], cd[3])
			
			for facet in face.facets:
				var normal = Vector3(facet.normal[0], facet.normal[1], facet.normal[2])
				for vertex in [facet.vertices[0], facet.vertices[2], facet.vertices[1]]:
					normals.append(normal)
					verts.append(Vector3(vertex[0], vertex[1], vertex[2]) * 39.3700787)
					colors.append(color)
			
			face_index += 1
	
	var arr = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	
	$Faces.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
