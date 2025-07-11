// Booboot - The scawy bootloaderrr
// Copyright (C) 2025   Keyb <contact@keyb.moe>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pub const MapFlag = struct {
    pub const none: u8 = 1 << 0;
    pub const read: u8 = 1 << 1;
    pub const write: u8 = 1 << 2;
    pub const execute: u8 = 1 << 3;
    pub const user: u8 = 1 << 4;
    pub const huge: u8 = 1 << 5;
};
