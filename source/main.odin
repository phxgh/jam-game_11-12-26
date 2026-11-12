package main

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
THING_PLAYER :: Thing{.Player, .Solid}

PLR_SIZE :: 24
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
	solids: [512]Solid
	
	plr_idx := append(&current_state.things, THING_PLAYER) - 1
	solids[plr_idx]={body={width=PLR_SIZE, height=PLR_SIZE}}

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
			for flag in Thing_Flag {
				switch flag {
				case .Player:
					iv: Vec2
					if input.state[.Up] == .Down do iv.y -= 1
					if input.state[.Down] == .Down do iv.y += 1
					if input.state[.Left] == .Down do iv.x -= 1
					if input.state[.Right] == .Down do iv.x += 1
					iv = linalg.normalize0(iv)
					solid.vel = iv * PLR_SPEED
					fallthrough

				case .Solid:
					solid.body.x += solid.vel.x * dt
					solid.body.y += solid.vel.y * dt
				}
			}
		}

		rl.BeginDrawing()
		{
			rl.ClearBackground(current_state.bg_color)
			for thing, idx in current_state.things {
				if .Solid in thing {
					solid := solids[idx]
					size := Vec2{solid.body.width, solid.body.height}
					rl.DrawRectanglePro(solid.body, size/2, 0, rl.RED)
				}
			}
		}
		rl.EndDrawing()
	}
}

INPUT_DEF_BINDINGS :: [Input_Control]Input_Control_Binding{
	.Up = {rl.KeyboardKey.W, nil},
	.Down = {rl.KeyboardKey.S, nil},
	.Left = {rl.KeyboardKey.A, nil},
	.Right = {rl.KeyboardKey.D, nil},
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

Thing :: bit_set[Thing_Flag; u8]

Thing_Flag :: enum u8 {
	Player,
	Solid,
}

