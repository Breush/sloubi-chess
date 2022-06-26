// A row/col encoded as 0b[RE_CE][R1_R2_R3][C1_C2_C3] on 3 bits each with 1 more each:
// RE and CE are error bits, the corresponding row/col is invalid when they are on.
// So numbers between 0 and 63 are valid, and all above are invalid.
Coord :: u8;
CoordCount :: 64;

coord :: (row : u8, col : u8) -> Coord {
    coord : Coord;
    if row >= 8 then coord |= 0b10_000_000;
    else coord |= row << 3;
    if col >= 8 then coord |= 0b01_000_000;
    else coord |= col;
    return coord;
}

coord_same_col :: (coord1 : Coord, coord2 : Coord) -> bool {
    return (coord1 & 0b01_000_111 == coord2 & 0b01_000_111);
}

coord_same_ignoring_invalid :: (coord1 : Coord, coord2 : Coord) -> bool {
    if (coord1 & 0b10_000_000 == 0) && (coord2 & 0b10_000_000 == 0) &&
       (coord1 & 0b00_111_000 != coord2 & 0b00_111_000) {
        return false;
    }
    if (coord1 & 0b01_000_000 == 0) && (coord2 & 0b01_000_000 == 0) &&
       (coord1 & 0b00_000_111 != coord2 & 0b00_000_111) {
        return false;
    }
    return true;
}

coord_copy_row :: (coord : *Coord, sourceCoord : Coord) {
    <<coord &= 0b01_000_111;
    <<coord |= sourceCoord & 0b10_111_000;
}

coord_copy_col :: (coord : *Coord, sourceCoord : Coord) {
    <<coord &= 0b10_111_000;
    <<coord |= sourceCoord & 0b01_000_111;
}

coord_is_valid :: (coord : Coord) -> bool {
    return (coord & 0b11_000_000) == 0;
}

coord_to_algebraic :: (coord : Coord, silentOnInvalid := false) -> string {
    s := Basic.tprint("??");

    if coord & 0b10_000_000 == 0 then s[1] = #char "1" + ((coord >> 3) & 0b0000_0111);
    else if silentOnInvalid then s.count -= 1;

    if coord & 0b01_000_000 == 0 then s[0] = #char "a" + (coord & 0b0000_0111);
    else if silentOnInvalid then Basic.advance(*s, 1);

    return s;
}

algebraic_to_coord :: (s : string) -> Coord {
    col := s[0] - #char "a";
    row := s[1] - #char "1";
    return coord(row, col);
}

coords_direction :: (fromCoord : Coord, toCoord : Coord) -> Chamber.vec2 {
    fromRow, fromCol := row_col(fromCoord);
    toRow, toCol := row_col(toCoord);

    v : Chamber.vec2 = ---;
    v.x = cast(float) toCol - cast(float) fromCol;
    v.y = cast(float) fromRow - cast(float) toRow; // @note Screen convention is Y negative.
    return v;
}

// Return 0xFF if a component is invalid.
row_col :: (coord : Coord) -> (row : u8, col : u8) {
    row, col : u8;

    if coord & 0b10_000_000 != 0 then row = 0xFF;
    else row = (coord >> 3) & 0b0000_0111;

    if coord & 0b01_000_000 != 0 then col = 0xFF;
    else col = coord & 0b0000_0111;

    return (row, col);
}

row_col_to_algebraic :: (row : u8, col : u8, silentOnInvalid := false) -> string {
    return coord_to_algebraic(coord(row, col), silentOnInvalid);
}
