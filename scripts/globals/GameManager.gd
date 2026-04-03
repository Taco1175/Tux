extends Node

# Game states
enum State {
	MAIN_MENU,
	LOBBY,
	HUB,
	LOADING,
	IN_GAME,
	PAUSED,
	GAME_OVER,
	ENDING
}

# Ending choices (all 4 paths)
enum EndingChoice {
	NONE,
	LET_PARENTS_GO,       # Path A: parents sacrifice, siblings surface alone
	SIBLING_STAYS,        # Path B: a sibling takes their place
	EXPOSE_AND_REFUSE,    # Path C: surface, blow the whistle, find another way
	REIMPRISION_THE_GOD   # Path D: everyone goes home, evil persists, you know
}

var current_state: State = State.MAIN_MENU
var current_run: RunData = null
var ending_choice: EndingChoice = EndingChoice.NONE

# Emitted when state changes
signal state_changed(new_state: State)
signal run_started(run_data: RunData)
signal run_ended(ending: EndingChoice)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Load saved key bindings at startup
	var HUD := load("res://scenes/ui/HUD.gd")
	if HUD:
		HUD.load_keybinds()


func change_state(new_state: State) -> void:
	current_state = new_state
	state_changed.emit(new_state)


func start_run(selected_classes: Array[int]) -> void:
	current_run = RunData.new()
	current_run.run_seed = randi()
	current_run.selected_classes = selected_classes
	current_run.floor_number = 0
	current_run.run_currency = 0
	run_started.emit(current_run)
	change_state(State.LOADING)


func end_run(choice: EndingChoice) -> void:
	ending_choice = choice
	if current_run:
		UnlockManager.process_run_end(current_run, choice)
	run_ended.emit(choice)
	change_state(State.GAME_OVER)


func return_to_hub() -> void:
	current_run = null
	change_state(State.HUB)
	get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")


func enter_dungeon(selected_classes: Array[int]) -> void:
	start_run(selected_classes)
	change_state(State.IN_GAME)
	get_tree().change_scene_to_file("res://scenes/game/Game.tscn")


func pause_game() -> void:
	if current_state == State.IN_GAME:
		get_tree().paused = true
		change_state(State.PAUSED)


func resume_game() -> void:
	if current_state == State.PAUSED:
		get_tree().paused = false
		change_state(State.IN_GAME)


# -------------------------------------------------------
# RunData: tracks all state for a single run
# -------------------------------------------------------
class RunData:
	var run_seed: int = 0
	var floor_number: int = 0
	var run_currency: int = 0          # "tide tokens" — spent in unlock shop
	var selected_classes: Array[int] = []
	var players_alive: Array[int] = [] # peer IDs still in the run
	var enemies_killed: int = 0
	var colony_secret_known: bool = false  # true once the mural is found in zone 2
	var parents_found: bool = false        # true once players reach the sanctum
	var sibling_sacrificed_peer: int = -1  # peer ID if Path B chosen
	var collected_items: Array = []       # inventory snapshot for item save screen
