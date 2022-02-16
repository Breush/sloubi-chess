load_fen :: (fen : string) -> Position {
    position : Position;

    row : u8 = 7;
    col : u8;

    s := fen;
    while s[0] != #char " " {
        c := s[0];
        if c == #char "/" {
            row -= 1;
            col = 0;
        } else if c >= #char "1" && c <= #char "8" {
            col += c - #char "0";
        } else {
            <<peek_piece_pointer(*position, cast(u8) row, cast(u8) col) = _fen_get_piece(c);
            col += 1;
        }

        Basic.advance(*s, 1);
    }
    Basic.advance(*s, 1);

    // Color to play
    if s[0] == #char "b" then position.moveIndex = 1;
    Basic.advance(*s, 2);

    // @todo Castling rights
    while s[0] != #char " " {
        Basic.advance(*s, 1);
    }
    Basic.advance(*s, 1);

    // @todo En passant square
    while s[0] != #char " " {
        Basic.advance(*s, 1);
    }
    Basic.advance(*s, 1);

    // @todo Halfmove clock
    while s[0] != #char " " {
        Basic.advance(*s, 1);
    }
    Basic.advance(*s, 1);

    // Fullmove number
    fullMoveNumber : int;
    ok : bool;
    fullMoveNumber, ok, s = Basic.to_integer(s);
    position.moveIndex += cast(u16) (fullMoveNumber - 1) * 2;

    return position;
}

fen_piece_to_string :: (piece : Piece) -> string {
    if piece.kind == .B && piece.color == .Black then return "b";
    if piece.kind == .K && piece.color == .Black then return "k";
    if piece.kind == .N && piece.color == .Black then return "n";
    if piece.kind == .P && piece.color == .Black then return "p";
    if piece.kind == .Q && piece.color == .Black then return "q";
    if piece.kind == .R && piece.color == .Black then return "r";
    if piece.kind == .B && piece.color == .White then return "B";
    if piece.kind == .K && piece.color == .White then return "K";
    if piece.kind == .N && piece.color == .White then return "N";
    if piece.kind == .P && piece.color == .White then return "P";
    if piece.kind == .Q && piece.color == .White then return "Q";
    if piece.kind == .R && piece.color == .White then return "R";
    return " ";
}

#scope_file

_fen_get_piece :: (fen : u8) -> Piece {
    if fen == #char "b" then return .{ .B, .Black };
    if fen == #char "k" then return .{ .K, .Black };
    if fen == #char "n" then return .{ .N, .Black };
    if fen == #char "p" then return .{ .P, .Black };
    if fen == #char "q" then return .{ .Q, .Black };
    if fen == #char "r" then return .{ .R, .Black };
    if fen == #char "B" then return .{ .B, .White };
    if fen == #char "K" then return .{ .K, .White };
    if fen == #char "N" then return .{ .N, .White };
    if fen == #char "P" then return .{ .P, .White };
    if fen == #char "Q" then return .{ .Q, .White };
    if fen == #char "R" then return .{ .R, .White };
    return .{ kind = .Empty };
}
