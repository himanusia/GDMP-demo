class_name VisionTask
extends Control

var main_scene := preload("res://Main.tscn")
var model_assets_dir := "user://GDMP/vision"
var request: HTTPRequest
var running_mode := MediaPipeVisionTask.RUNNING_MODE_IMAGE
var delegate := MediaPipeTaskBaseOptions.DELEGATE_CPU
var camera_helper: MediaPipeCameraHelper = MediaPipeCameraHelper.new()
var camera_extension := CameraServerExtension.new()
var camera_feed
var camera_texture := CameraTexture.new()
var use_camera_extension := true
var image_file_web: FileAccessWeb
var video_file_web: FileAccessWeb

@onready var progress_bar: ProgressBar = $VBoxContainer/ProgressBar
@onready var image_view: TextureRect = $VBoxContainer/Image
@onready var video_player: VideoStreamPlayer = $Video
@onready var btn_back: Button = $VBoxContainer/Title/Back
@onready var btn_load_image: Button = $VBoxContainer/Buttons/LoadImage
@onready var btn_load_video: Button = $VBoxContainer/Buttons/LoadVideo
@onready var btn_open_camera: Button = $VBoxContainer/Buttons/OpenCamera
@onready var image_file_dialog: FileDialog = $ImageFileDialog
@onready var video_file_dialog: FileDialog = $VideoFileDialog
@onready var select_camera_dialog: ConfirmationDialog = $SelectCamera
@onready var opt_camera_feed: OptionButton = $SelectCamera/VBoxContainer/SelectFeed
@onready var opt_camera_format: OptionButton = $SelectCamera/VBoxContainer/SelectFormat
@onready var permission_dialog: AcceptDialog = $PermissionDialog

func _exit_tree() -> void:
	camera_extension = null

func _ready():
	btn_back.pressed.connect(self._back)
	btn_load_image.pressed.connect(self._open_image)
	btn_load_video.pressed.connect(self._open_video)
	btn_open_camera.pressed.connect(self._open_camera)
	image_file_dialog.file_selected.connect(self._load_image)
	video_file_dialog.file_selected.connect(self._load_video)
	if OS.get_name() == "Web":
		image_file_web = FileAccessWeb.new()
		video_file_web = FileAccessWeb.new()
		image_file_web.loaded.connect(self._load_image_web)
		video_file_web.loaded.connect(self._load_video_web)
	CameraServer.camera_feed_added.connect(self._camera_added)
	CameraServer.camera_feed_removed.connect(self._camera_removed)
	camera_extension.permission_result.connect(self._camera_permission_result)
	select_camera_dialog.get_ok_button().disabled = true
	var feeds = CameraServer.feeds()
	for feed in feeds:
		opt_camera_feed.add_item(feed.get_name(), feed.get_id())
		opt_camera_feed.selected = -1
	opt_camera_feed.item_selected.connect(self._camera_selected)
	opt_camera_format.item_selected.connect(self._format_selected)
	select_camera_dialog.confirmed.connect(self._start_camera)
	camera_helper.permission_result.connect(self._camera_permission_result)
	camera_helper.new_frame.connect(self._camera_frame)
	_init_task()

func _process(_delta: float) -> void:
	if request:
		var max_size := request.get_body_size()
		var cur_size := request.get_downloaded_bytes()
		progress_bar.value = round(float(cur_size) / float(max_size) * 100)
	if video_player.is_playing():
		var texture := video_player.get_video_texture()
		if texture:
			var image := texture.get_image()
			if image:
				if not running_mode == MediaPipeVisionTask.RUNNING_MODE_VIDEO:
					running_mode = MediaPipeVisionTask.RUNNING_MODE_VIDEO
					_init_task()
				_process_video(image, Time.get_ticks_msec())

func _reset() -> void:
	video_player.stop()
	if camera_feed:
		camera_feed.feed_is_active = false
		if camera_feed.frame_changed.is_connected(self._camera_feed_frame):
			camera_feed.frame_changed.disconnect(self._camera_feed_frame)
	camera_helper.close()

func _back() -> void:
	_reset()
	get_tree().change_scene_to_packed(main_scene)

func _get_model_asset(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, path: String) -> void:
	progress_bar.hide()
	image_view.show()
	if result != HTTPRequest.RESULT_SUCCESS:
		return
	if response_code != HTTPClient.RESPONSE_OK:
		return
	if body.is_empty():
		return
	if DirAccess.make_dir_recursive_absolute(model_assets_dir) != OK:
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(body)
	file.close()
	request = null
	_init_task()

func _init_task() -> void:
	btn_load_image.disabled = false
	btn_load_video.disabled = false
	if OS.get_name() != "Web":
		btn_open_camera.disabled = false

func _open_image() -> void:
	_reset()
	if OS.get_name() == "Web":
		image_file_web.open("*.bmp, *.jpg, *.png")
	else:
		image_file_dialog.popup_centered_ratio()

func _load_image(path: String) -> void:
	if not running_mode == MediaPipeVisionTask.RUNNING_MODE_IMAGE:
		running_mode = MediaPipeVisionTask.RUNNING_MODE_IMAGE
		_init_task()
	var image := Image.load_from_file(path)
	_process_image(image)

func _load_image_web(_file_name: String, type: String, base64_data: String) -> void:
	var data := Marshalls.base64_to_raw(base64_data)
	var image := Image.new()
	if type == "image/jpeg":
		image.load_jpg_from_buffer(data)
	elif type == "image/png":
		image.load_png_from_buffer(data)
	elif type == "image/bmp":
		image.load_bmp_from_buffer(data)
	_process_image(image)

func _open_video() -> void:
	_reset()
	if OS.get_name() == "Web":
		pass
	else:
		video_file_dialog.popup_centered_ratio()

func _load_video(path: String) -> void:
	var stream: VideoStream = load(path)
	video_player.stream = stream
	video_player.play()

func _load_video_web(_file_name: String, _type: String, _base64_data: String) -> void:
	# no support yet
	pass

func _open_camera() -> void:
	_reset()
	if use_camera_extension:
		if camera_extension.permission_granted():
			_select_camera()
		else:
			camera_extension.request_permission()
			if OS.get_name() == "Windows":
				btn_open_camera.disabled = true
	else:
		if camera_helper.permission_granted():
			_start_camera()
		else:
			camera_helper.request_permission()

func _camera_permission_result(granted: bool) -> void:
	if granted:
		if use_camera_extension:
			_select_camera()
		else:
			_start_camera()
	else:
		permission_dialog.popup_centered()

func _select_camera() -> void:
	select_camera_dialog.popup_centered.call_deferred()

func _camera_selected(_index: int) -> void:
	if camera_feed:
		camera_feed = null
	opt_camera_format.clear()
	select_camera_dialog.get_ok_button().disabled = true
	var id := opt_camera_feed.get_selected_id()
	for feed in CameraServer.feeds():
		if feed.get_id() == id:
			camera_feed = feed
			break
	if camera_feed == null:
		return
	var formats = camera_feed.get_formats()
	for format in formats:
		if format.has("frame_numerator") and format.has("frame_denominator"):
			format["fps"] = round(format["frame_denominator"] / format["frame_numerator"])
		if format.has("framerate_numerator") and format.has("framerate_denominator"):
			format["fps"] = round(format["framerate_numerator"] / format["framerate_denominator"])
		opt_camera_format.add_item(String("{width}x{height}@{fps}({format})").format(format))
		opt_camera_format.selected = -1

func _format_selected(index: int) -> void:
	if camera_feed == null:
		return
	if camera_feed.set_format(index, {}):
		select_camera_dialog.get_ok_button().disabled = false
	else:
		select_camera_dialog.get_ok_button().disabled = true

func _start_camera() -> void:
	if use_camera_extension:
		camera_texture.camera_feed_id = camera_feed.get_id()
		camera_feed.frame_changed.connect(self._camera_feed_frame)
		camera_feed.feed_is_active = true
	else:
		camera_helper.set_mirrored(true)
		camera_helper.start(MediaPipeCameraHelper.FACING_FRONT, Vector2(640, 480))

func _camera_added(id: int):
	for i in range(opt_camera_feed.item_count):
		if opt_camera_feed.get_item_id(i) == id:
			return
	var feeds = CameraServer.feeds()
	for feed in feeds:
		if feed.get_id() == id:
			var idx := opt_camera_feed.selected
			opt_camera_feed.add_item.call_deferred(feed.get_name(), id)
			opt_camera_feed.select.call_deferred(idx)

func _camera_removed(id: int):
	if opt_camera_feed.get_selected_id() == id:
		opt_camera_format.clear.call_deferred()
	for i in range(opt_camera_feed.item_count):
		if opt_camera_feed.get_item_id(i) == id:
			opt_camera_feed.remove_item.call_deferred(i)
			opt_camera_feed.select.call_deferred(-1)
	if camera_feed != null and camera_feed.get_id() == id:
		camera_feed = null

func _camera_feed_frame() -> void:
	if camera_texture == null:
		return
	var image := camera_texture.get_image()
	if image == null:
		return
	var img := MediaPipeImage.new()
	img.set_image(image)
	_camera_frame(img)

func _camera_frame(image: MediaPipeImage) -> void:
	if not running_mode == MediaPipeVisionTask.RUNNING_MODE_LIVE_STREAM:
		running_mode = MediaPipeVisionTask.RUNNING_MODE_LIVE_STREAM
		_init_task()
	if delegate == MediaPipeTaskBaseOptions.DELEGATE_CPU and image.is_gpu_image():
		image.convert_to_cpu()
	_process_camera(image, Time.get_ticks_msec())

func _process_image(_image: Image) -> void:
	pass

func _process_video(_image: Image, _timestamp_ms: int) -> void:
	pass

func _process_camera(_image: MediaPipeImage, _timestamp_ms: int) -> void:
	pass

func get_model_asset(filename: String, generation: int = -1) -> FileAccess:
	var path := model_assets_dir.path_join(filename)
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		return file
	if Global.enable_download_files:
		request = MediaPipeExternalFiles.get_asset(filename, generation)
		if request != null:
			image_view.hide()
			progress_bar.show()
			var callback := _get_model_asset.bind(path)
			request.request_completed.connect(callback)
	return null

func update_image(image: Image) -> void:
	if Vector2i(image_view.texture.get_size()) == image.get_size():
		image_view.texture.call_deferred("update", image)
	else:
		image_view.texture.call_deferred("set_image", image)
