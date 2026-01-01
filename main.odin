package main

import "core:fmt"
import "core:time"
import "core:c/libc"
import x "vendor:x11/xlib"

MOVE_SEQUENCE := [4]x.KeySym{.XK_Right, .XK_Up, .XK_Right, .XK_Down}
REPEAT_COUNT :: 5
KEY_DELAY_MS :: 80  // Delay between key presses in milliseconds

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
	XTestFakeKeyEvent(display, cast(u32)keycode, true, 0)
	x.Flush(display)
	time.sleep(time.Millisecond * 50)
	XTestFakeKeyEvent(display, cast(u32)keycode, false, 0)
	x.Flush(display)
}

perform_difficult_move :: proc(display: ^x.Display) {
	fmt.println("Performing difficult move: (Right, Up, Left, Down) x", REPEAT_COUNT)
	
	for i in 0..<REPEAT_COUNT {
		fmt.println("  Cycle", i + 1, "of", REPEAT_COUNT)
		for keysym in MOVE_SEQUENCE {
			simulate_key_press(display, keysym)
			time.sleep(time.Millisecond * KEY_DELAY_MS)
		}
	}
	
	fmt.println("Difficult move completed!")
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
	ctrl_mod2 := x.InputMask{.ControlMask, .Mod2Mask}  // NumLock
	ctrl_lock_mod2 := x.InputMask{.ControlMask, .LockMask, .Mod2Mask}
	
	x.GrabKey(display, cast(i32)f1_keycode, ctrl_mask, root, true, .GrabModeAsync, .GrabModeAsync)
	x.GrabKey(display, cast(i32)f1_keycode, ctrl_lock, root, true, .GrabModeAsync, .GrabModeAsync)
	x.GrabKey(display, cast(i32)f1_keycode, ctrl_mod2, root, true, .GrabModeAsync, .GrabModeAsync)
	x.GrabKey(display, cast(i32)f1_keycode, ctrl_lock_mod2, root, true, .GrabModeAsync, .GrabModeAsync)
	
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
				fmt.println("Ctrl+F1 pressed! Starting macro in 500ms...")
				
				// Brief delay to let user release keys
				time.sleep(time.Millisecond * 500)
				
				perform_difficult_move(display)
				
				fmt.println("")
				fmt.println("Ready for next Ctrl+F1...")
			}
		}
	}
}
