const std = @import("std");

const c = @import("c");

const WIDTH = 1080;
const HEIGHT = 1020;

// --- The Random Walker ---
pub const Walker = struct {
    x: f32,
    y: f32,

    pub fn init() Walker {
        return .{ .x = WIDTH / 2.0, .y = HEIGHT / 2.0 };
    }

    pub fn step(self: *Walker, rand: std.Random) void {
        const choice = rand.uintLessThan(u8, 4);

        if (choice == 0) { self.x += 1.0; } 
        else if (choice == 1) { self.x -= 1.0; } 
        else if (choice == 2) { self.y += 1.0; } 
        else { self.y -= 1.0; }

        self.x = std.math.clamp(self.x, 0, WIDTH - 1);
        self.y = std.math.clamp(self.y, 0, HEIGHT - 1);
    }

    pub fn display(self: *const Walker) void {
        c.glColor3f(1.0, 1.0, 1.0);
        c.glBegin(c.GL_POINTS);
        c.glVertex2f(self.x, self.y);
        c.glEnd();
    }
};

pub fn main() !void {
    // 1. Open a connection to the native X Server
    const display = c.XOpenDisplay(null) orelse return error.CannotOpenDisplay;
    defer _ = c.XCloseDisplay(display);

    const root = c.XDefaultRootWindow(display);

    // 2. Query OpenGL Visual Attributes 
    var att = [_]c_int{
        c.GLX_RGBA,
        c.GLX_DOUBLEBUFFER, // Enable double buffering
        c.GLX_DEPTH_SIZE, 24,
        c.None,
    };

    const vi = c.glXChooseVisual(display, 0, &att[0]) orelse return error.NoAppropriateVisual;
    defer _ = c.XFree(vi);

    // 3. Create X11 Window Attributes & Colormap
    const cmap = c.XCreateColormap(display, root, vi.*.visual, c.AllocNone);
    
    var swa: c.XSetWindowAttributes = std.mem.zeroes(c.XSetWindowAttributes);
    swa.colormap = cmap;
    swa.event_mask = c.ExposureMask | c.KeyPressMask;

    // 4. Create the Actual Window on the Desktop
    const win = c.XCreateWindow(
        display, root, 
        0, 0, WIDTH, HEIGHT, 0, 
        vi.*.depth, c.InputOutput, vi.*.visual, 
        c.CWColormap | c.CWEventMask, &swa
    );

    _ = c.XMapWindow(display, win);
    _ = c.XStoreName(display, win, "Nature of Code - Raw X11/GLX");

    // Intercept Window Manager Close Button Event (so closing the window exits cleanly)
    var wm_delete_window = c.XInternAtom(display, "WM_DELETE_WINDOW", c.False);
    _ = c.XSetWMProtocols(display, win, &wm_delete_window, 1);

    // 5. Create and Bind the Native OpenGL Context
    const glc = c.glXCreateContext(display, vi, null, c.GL_TRUE) orelse return error.CannotCreateGLContext;
    _ = c.glXMakeCurrent(display, win, glc);
    defer {
        _ = c.glXMakeCurrent(display, c.None, null);
        c.glXDestroyContext(display, glc);
    }

    // 6. Initialize OpenGL Viewport & Orthographic Camera
    c.glViewport(0, 0, WIDTH, HEIGHT);
    c.glMatrixMode(c.GL_PROJECTION);
    c.glLoadIdentity();
    c.glOrtho(0, WIDTH, 0, HEIGHT, -1, 1);
    c.glMatrixMode(c.GL_MODELVIEW);
    c.glLoadIdentity();

    // Fill background with White ONCE (Mimics Processing's setup behavior)
    c.glClearColor(0.0, 0.0, 0.0, 0.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT);
    c.glXSwapBuffers(display, win); // Populate both front and back buffers
    c.glClear(c.GL_COLOR_BUFFER_BIT);

    // Setup PRNG
    var prng = std.Random.DefaultPrng.init(12345);
    const rand = prng.random();
    var walker = Walker.init();

    // 7. Main Native Event Loop
    var xev: c.XEvent = undefined;
    var running = true;

    while (running) {
        // Check if X11 has sent events (resizing, closing, key presses)
        while (c.XPending(display) > 0) {
            _ = c.XNextEvent(display, &xev);
            
            if (xev.type == c.ClientMessage) {
                if (xev.xclient.data.l[0] == wm_delete_window) {
                    running = false;
                }
            } else if (xev.type == c.KeyPress) {
                // Pressing Escape exits
                if (c.XLookupKeysym(&xev.xkey, 0) == c.XK_Escape) {
                    running = false;
                }
            }
        }

        if (!running) break;

        // --- Processing's draw() Equivalent ---
        walker.step(rand);
        walker.display();

        // Swap back buffer to front buffer to show the newly rendered pixel
        c.glXSwapBuffers(display, win);
        
        // Pacing: roughly 60 updates a second
        var delay: c.timespec = undefined;
        delay.tv_sec = 0;
        delay.tv_nsec = 16 * 1_000_000;

        _ = c.nanosleep(&delay, null);
    }
}
