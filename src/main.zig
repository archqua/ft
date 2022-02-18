const main_window_module = @import("main_window.zig");
const MainWindow = main_window_module.MainWindow;

pub fn main() u8 {
    if (MainWindow.init()) |*main_window| {
        return main_window.runUntilComplete();
    } else |err| {
        switch (err) {
            //
        }
    }
    return 0;
}
