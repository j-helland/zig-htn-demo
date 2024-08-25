pub const MAX_FPS = 60.0;  // seconds

pub const DEFAULT_WINDOW_WIDTH = 1280;
pub const DEFAULT_WINDOW_HEIGHT = 720;
pub const DEFAULT_WORLD_WIDTH = 1280;
pub const DEFAULT_WORLD_HEIGHT = 1280;
pub const NAV_MESH_GRID_CELL_SIZE = 0.025;

pub const MAX_KEYBOARD_KEYS = 350;
pub const MAX_MOUSE_BUTTONS = 5;
pub const MAX_SOUND_CHANNELS = 16;

pub const PLAYER_SPEED = 6.0 / @as(f32, @floatFromInt(DEFAULT_WINDOW_WIDTH));
pub const PLAYER_SCALE = 0.15;
pub const PLAYER_FOV = 35;

pub const ENEMY_SCALE = 0.25;
pub const ENEMY_SPEED = 4.0 / @as(f32, @floatFromInt(DEFAULT_WINDOW_WIDTH));
pub const ENEMY_ATTACK_RANGE = 0.025;
pub const ENEMY_FREEZE_TIME = 750000000;            // nanoseconds
pub const ENEMY_FREEZE_TIME_RNG_BOUND = 750000000;  // nanoseconds

pub const WALL_WIDTH = 300;
pub const WALL_HEIGHT = 50;
