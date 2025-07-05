extends VisionTask

var task: MediaPipeGestureRecognizer
var task_file := "gesture_recognizer.task"
var task_file_generation := 1677051715043311

@onready var lbl_gesture: Label = $VBoxContainer/Image/Gesture

func _result_callback(result: MediaPipeGestureRecognizerResult, image: MediaPipeImage, timestamp_ms: int) -> void:
	var img := image.get_image()
	show_result(img, result)

func _init_task() -> void:
	var file := get_model_asset(task_file, task_file_generation)
	if file == null:
		return
	var base_options := MediaPipeTaskBaseOptions.new()
	base_options.delegate = delegate
	base_options.model_asset_buffer = file.get_buffer(file.get_length())
	task = MediaPipeGestureRecognizer.new()
	task.initialize(base_options, running_mode)
	task.result_callback.connect(self._result_callback)
	super()

func _process_image(image: Image) -> void:
	var input_image := MediaPipeImage.new()
	input_image.set_image(image)
	var result := task.recognize(input_image)
	show_result(image, result)

func _process_video(image: Image, timestamp_ms: int) -> void:
	var input_image := MediaPipeImage.new()
	input_image.set_image(image)
	var result := task.recognize_video(input_image, timestamp_ms)
	show_result(image, result)

func _process_camera(image: MediaPipeImage, timestamp_ms: int) -> void:
	task.recognize_async(image, timestamp_ms)

func show_result(image: Image, result: MediaPipeGestureRecognizerResult) -> void:
	var gesture_text := ""
	var gestures = result.gestures
	var handedness = result.handedness
	assert(gestures.size() == handedness.size())
	for i in range(gestures.size()):
		var gesture = gestures[i]
		var hand = handedness[i]
		var classification_gesture: MediaPipeProto = gesture.get_repeated("classification", 0)
		var classification_hand: MediaPipeProto = hand.get_repeated("classification", 0)
		var gesture_label: String = classification_gesture.get("label")
		var gesture_score: float = classification_gesture.get("score")
		var hand_label: String = classification_hand.get("label")
		var hand_score: float = classification_hand.get("score")
		gesture_text += "%s: %.2f\n%s: %.2f\n\n" % [hand_label, hand_score, gesture_label, gesture_score]
	lbl_gesture.call_deferred("set_text", gesture_text)
	update_image(image)
