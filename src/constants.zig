pub const INPUT_PREFIX = "sklient> ";

pub const Key = union(enum) {
    char: u8,
    arrow_up,
    arrow_down,
};

pub const Keys = struct {
    pub const CTRL_C: u8 = 3;
    pub const ENTER: u8 = 10;
    pub const CTRL_T: u8 = 20;
    pub const BACKSPACE: u8 = 127;
};
