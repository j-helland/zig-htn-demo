pub const DEFAULT_WINDOW_WIDTH = 1280;
pub const DEFAULT_WINDOW_HEIGHT = 720;
pub const MAX_KEYBOARD_KEYS = 350;
pub const MAX_MOUSE_BUTTONS = 5;
pub const MAX_SOUND_CHANNELS = 16;

pub const PLAYER_SPEED = 8.0 / @intToFloat(f32, DEFAULT_WINDOW_WIDTH);
pub const PLAYER_SCALE = 0.25;
pub const PLAYER_FOV = 180;

pub const ENEMY_SPEED = 4.0 / @intToFloat(f32, DEFAULT_WINDOW_WIDTH);
pub const ENEMY_ATTACK_RANGE = 1e-2;

// pub const NAV_MESH_GRID_CELL_SIZE = 0.025;
pub const NAV_MESH_GRID_CELL_SIZE = 0.01;
