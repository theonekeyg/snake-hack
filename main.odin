package main

import "core:c/libc"
import "core:fmt"
import "core:time"
import x "vendor:x11/xlib"

MOVE_SEQUENCE := [5]x.KeySym{.XK_Right, .XK_Up, .XK_Right, .XK_Down, .XK_Right}
REPEAT_COUNT :: 5
KEY_DELAY_MS :: 70 // Delay between key presses in milliseconds

// Foreign import for XTest extension
foreign import xtest "system:Xtst"

foreign xtest {
	@(link_name = "XTestFakeKeyEvent")
	XTestFakeKeyEvent :: proc "c" (display: ^x.Display, keycode: u32, is_press: b32, delay: u64) -> i32 ---
}

simulate_key_press :: proc(display: ^x.Display, keysym: x.KeySym) {
	keycode := x.KeysymToKeycode(display, keysym)
	if keycode == 0 {
		fmt.println("Failed to get keycode for keysym:", keysym)
		return
	}

	// Press and release the key using XTest
	// Keep hold time short (<1 game frame) to avoid double-registration
	XTestFakeKeyEvent(display, cast(u32)keycode, true, 0)
	x.Flush(display)
	time.sleep(time.Millisecond * 40)
	XTestFakeKeyEvent(display, cast(u32)keycode, false, 0)
	x.Flush(display)
}

// Check if a key is currently pressed using XQueryKeymap (no grabbing needed)
is_key_pressed :: proc(display: ^x.Display, keycode: u8) -> bool {
	keys: [8]u32 // 256 bits = 8 x 32-bit words
	x.QueryKeymap(display, raw_data(&keys))
	word_idx := keycode / 32
	bit_idx := keycode % 32
	return (keys[word_idx] & (1 << bit_idx)) != 0
}

// Check if any arrow key is currently held down
check_arrow_interrupt :: proc(display: ^x.Display, arrow_keycodes: [4]x.KeyCode) -> bool {
	for kc in arrow_keycodes {
		if is_key_pressed(display, kc) {
			return true
		}
	}
	return false
}

perform_difficult_move :: proc(display: ^x.Display) -> bool {
	fmt.println("Performing difficult move: (Right, Up, Left, Down) x", REPEAT_COUNT)
	fmt.println("  (Hold any arrow key to interrupt)")

	// Get arrow keycodes once
	arrow_keycodes := [4]x.KeyCode {
		x.KeysymToKeycode(display, .XK_Up),
		x.KeysymToKeycode(display, .XK_Down),
		x.KeysymToKeycode(display, .XK_Left),
		x.KeysymToKeycode(display, .XK_Right),
	}

	interrupted := false
	for i in 0 ..< REPEAT_COUNT {
		fmt.println("  Cycle", i + 1, "of", REPEAT_COUNT)

		// Complete the full sequence before checking for interrupt
		for keysym in MOVE_SEQUENCE {
			simulate_key_press(display, keysym)
			time.sleep(time.Millisecond * KEY_DELAY_MS)
		}

		// Check for interrupt only AFTER completing a full cycle
		if check_arrow_interrupt(display, arrow_keycodes) {
			fmt.println("  ** Interrupt detected - stopping after this cycle **")
			interrupted = true
			break
		}
	}

	if !interrupted {
		fmt.println("Difficult move completed!")
	} else {
		fmt.println("  Sequence safely finished, control returned to user.")
	}
	return !interrupted
}

main :: proc() {
	fmt.println("=== Snake Difficult Move Macro ===")
	fmt.println("Move sequence: Right -> Up -> Left -> Down (x5)")
	fmt.println("")
	fmt.println("Press Ctrl+F1 to trigger the macro")
	fmt.println("Press Ctrl+C to exit")
	fmt.println("")

	display := x.OpenDisplay(nil)
	if display == nil {
		fmt.println("Failed to open X display")
		return
	}
	defer x.CloseDisplay(display)

	root := x.DefaultRootWindow(display)

	// Get keycode for F1
	f1_keycode := x.KeysymToKeycode(display, .XK_F1)

	// Grab Ctrl+F1 globally
	// We need to grab with different lock states (CapsLock, NumLock combinations)
	ctrl_mask := x.InputMask{.ControlMask}
	ctrl_lock := x.InputMask{.ControlMask, .LockMask}
	ctrl_mod2 := x.InputMask{.ControlMask, .Mod2Mask} // NumLock
	ctrl_lock_mod2 := x.InputMask{.ControlMask, .LockMask, .Mod2Mask}

	x.GrabKey(display, cast(i32)f1_keycode, ctrl_mask, root, true, .GrabModeAsync, .GrabModeAsync)
	x.GrabKey(display, cast(i32)f1_keycode, ctrl_lock, root, true, .GrabModeAsync, .GrabModeAsync)
	x.GrabKey(display, cast(i32)f1_keycode, ctrl_mod2, root, true, .GrabModeAsync, .GrabModeAsync)
	x.GrabKey(
		display,
		cast(i32)f1_keycode,
		ctrl_lock_mod2,
		root,
		true,
		.GrabModeAsync,
		.GrabModeAsync,
	)

	x.SelectInput(display, root, {.KeyPress})

	fmt.println("Listening for Ctrl+F1...")

	event: x.XEvent
	for {
		x.NextEvent(display, &event)

		if event.type == .KeyPress {
			key_event := &event.xkey
			keysym := x.LookupKeysym(key_event, 0)

			// Check if it's F1 with Ctrl held
			has_ctrl := .ControlMask in key_event.state
			if keysym == .XK_F1 && has_ctrl {
				fmt.println("")
				fmt.println("Ctrl+F1 pressed! Starting macro")

				perform_difficult_move(display)

				fmt.println("")
				fmt.println("Ready for next Ctrl+F1...")
			}
		}
	}
}
