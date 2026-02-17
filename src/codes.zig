pub const NEW_SCREEN = "\x1b[?1049h\x1b[2J\x1b[H";
pub const EXIT_SCREEN = "\x1b[2J\x1b[H\x1b[?1049l";
pub const CLEAR_SCREEN = "\x1b[H\x1b[2J";

pub const HIGHLIGHT = "\x1b[7m";
pub const UNDERLINE_START = "\x1b[4m";
pub const UNDERLINE_END = "\x1b[24m";
pub const BOLD_START = "\x1b[1m";
pub const BOLD_END = "\x1b[22m";
pub const RESET = "\x1b[0m";
pub const GREY = "\x1b[90m";
