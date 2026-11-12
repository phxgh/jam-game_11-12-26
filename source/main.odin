package main

import "core:fmt"
import "core:math/linalg"
import "base:runtime"
import "core:log"
import vmem "core:mem/virtual"

import rl "vendor:raylib"

Vec2 :: rl.Vector2
Vec3 :: rl.Vector3
Rect :: rl.Rectangle

DEF_BG_COLOR :: rl.BLACK

THINGS_MAX :: 512
THING_PLAYER :: Thing{.Player, {.Solid, .Texture}}
THING_CHEST :: Thing{.Chest, {.Solid, .Texture}}

TILE_SIZE :: 16

PLR_CAM_ZOOM :: 4
PLR_SIZE :: TILE_SIZE
PLR_SPEED :: PLR_SIZE * 2

WIN_WIDTH :: 800
WIN_HEIGHT :: 600
WIN_TITLE :: ""

main :: proc() {
	arena: vmem.Arena; arena_err := vmem.arena_init_static(&arena)
	assert(arena_err == nil, "Failed to create memory allocator")
	defer vmem.arena_destroy(&arena)
	context.allocator = vmem.arena_allocator(&arena)

	when ODIN_DEBUG {
		rl.SetTraceLogLevel(.ERROR)
		context.logger = log.create_console_logger()
	} else {
		rl.SetTraceLogLevel(.NONE)
	}

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .WINDOW_HIGHDPI})
	rl.InitWindow(WIN_WIDTH, WIN_HEIGHT, WIN_TITLE)
	defer rl.CloseWindow()

	width, height := (f32)(rl.GetRenderWidth()), (f32)(rl.GetRenderHeight())

	input: Input
	// TODO: Load from file
	input.bindings = INPUT_DEF_BINDINGS

	state := State.Gameplay
	current_state := new(State_Data); current_state^ = {
		bg_color = DEF_BG_COLOR,
		things = make([dynamic]Thing, 0, THINGS_MAX), 
	}

	Solid :: struct {
		body: Rect,
		vel: Vec2,
	}
	solids: [THINGS_MAX]Solid

	path: cstring = #directory + "../bin/assets/atlas.png"
	ta_texture := rl.LoadTexture(path)
	assert(ta_texture.id != 0, fmt.tprint(path))
	texture_atlas := Texture_Atlas{
		texture = ta_texture,
		source = {
			.Player = {0, 0, TILE_SIZE, TILE_SIZE},
			.Chest1 = {0, TILE_SIZE, TILE_SIZE, TILE_SIZE},
			.Chest2 = {TILE_SIZE, TILE_SIZE, TILE_SIZE, TILE_SIZE},
		},
	}

	Texture :: struct {
		id: Texture_ID,
		flags: Texture_Flags,
	}
	Texture_Flags :: bit_set[enum {
		Flip,
	}; u8]
	textures: [THINGS_MAX]Texture

	Interactable :: struct {
		flags: Interactable_Flags,
		interact: proc(^Interactable, ^State_Data),
	}
	Interactable_Flags :: bit_set[enum {
		Can_Interact,
		Already_Interacted,
	}; u8]
	interactables: [THINGS_MAX]Interactable

	plr_cam := rl.Camera2D{
		offset={width/2, height/2},
		zoom=PLR_CAM_ZOOM,
	}

	// TODO: Pack this into init function?
	append(&current_state.things, THING_PLAYER)
	plr_idx := 0
	solids[plr_idx] = {body={width=PLR_SIZE, height=PLR_SIZE}}
	textures[plr_idx] = {.Player, {}}
	
	append(&current_state.things, THING_CHEST)
	chest_idx := 1
	solids[chest_idx] = {body={width=TILE_SIZE, height=TILE_SIZE}}
	textures[chest_idx] = {.Chest1, {}}
	chest_interact_proc :: proc(self: ^Interactable, state_data: ^State_Data) {
		self.flags -= {.Can_Interact}
		self.flags += {.Already_Interacted}
		log.debug("Interacted!")
	}
	interactables[chest_idx] = {{.Can_Interact}, chest_interact_proc}

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		for control in Input_Control {
			bindings := &input.bindings[control]
			state := &input.state[control]
			for binding in bindings {
				if binding == nil {
					continue
				}
				switch v in binding {
				case rl.KeyboardKey:
					if rl.IsKeyPressed(v) {
						state^ = .Pressed
					} else if rl.IsKeyDown(v) {
						state^ = .Down
					} else if rl.IsKeyReleased(v) {
						state^ = .Released
					} else {
						state^ = .Up
					}
				case rl.MouseButton:
					if rl.IsMouseButtonPressed(v) {
						state^ = .Pressed
					} else if rl.IsMouseButtonDown(v) {
						state^ = .Down
					} else if rl.IsMouseButtonReleased(v) {
						state^ = .Released
					} else {
						state^ = .Up
					}
				}
			}
		}

		for thing, idx in current_state.things {
			solid := &solids[idx]
			texture := &textures[idx]
			interact := &interactables[idx]
			#partial switch thing.id {
			case .Player:
				iv: Vec2
				if input.state[.Up] == .Down do iv.y -= 1
				if input.state[.Down] == .Down do iv.y += 1
				if input.state[.Left] == .Down do iv.x -= 1
				if input.state[.Right] == .Down do iv.x += 1

				if iv.x < 0 do texture.flags += {.Flip}
				if iv.x > 0 do texture.flags -= {.Flip}

				solid.vel = iv * PLR_SPEED
			}
			for flag in Thing_Flag {
				#partial switch flag {
					case .Solid:
						solid.body.x += solid.vel.x * dt
						solid.body.y += solid.vel.y * dt
					case .Interactable:
						if input.state[.Accept] == .Pressed {
							if .Can_Interact in interact.flags {
								interact->interact(current_state)
							}
						}
				}
			}
		}

		rl.BeginDrawing()
		{
			rl.ClearBackground(current_state.bg_color)
			
			rl.BeginMode2D(plr_cam)
			for thing, idx in current_state.things {
				if .Texture not_in thing.flags {
					continue
				}
				solid := solids[idx]
				texture := textures[idx]
				rl.DrawTexturePro(texture_atlas.texture, texture_atlas.source[texture.id], solid.body, {solid.body.width/2, solid.body.height/2}, 0, rl.WHITE)
			}
			rl.EndMode2D()
		}
		rl.EndDrawing()
	}
}

INPUT_DEF_BINDINGS :: [Input_Control]Input_Control_Binding{
	.Up = {rl.KeyboardKey.W, nil},
	.Down = {rl.KeyboardKey.S, nil},
	.Left = {rl.KeyboardKey.A, nil},
	.Right = {rl.KeyboardKey.D, nil},
	.Accept = {rl.KeyboardKey.ENTER, nil},
	.UI_Accept = {rl.MouseButton.LEFT, nil},
	.UI_Deny = {rl.MouseButton.RIGHT, nil},
}

Input :: struct {
	bindings: [Input_Control]Input_Control_Binding,
	state: [Input_Control]Input_State,
}

Input_Control :: enum {
	Up,
	Down,
	Left,
	Right,
	Accept,

	UI_Accept,
	UI_Deny,
}

Input_Control_Binding :: distinct [2]union {
	rl.KeyboardKey,
	rl.MouseButton,
} 

Input_State :: enum {
	Up,
	Pressed,
	Down,
	Released,
}

State :: enum {
	Main_Menu,
	Gameplay,
}

State_Data :: struct {
	bg_color: rl.Color,
	things: [dynamic]Thing,
}

Texture_Atlas :: struct {
	texture: rl.Texture2D,
	source: [Texture_ID]Rect,
}

Texture_ID :: enum {
	Chest1,
	Chest2,
	Player,
}

Thing :: struct {
	id: Thing_ID,
	flags: bit_set[Thing_Flag; u8],
}

Thing_ID :: enum u8 {
	Player,
	Chest,
}

Thing_Flag :: enum u8 {
	Solid,
	Texture,
	Interactable,
}

