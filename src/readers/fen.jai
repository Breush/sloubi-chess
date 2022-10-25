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

    // Castling rights
    while s[0] != #char " " {
        position.flags |= fen_castling_to_position_flag(s[0]);
        Basic.advance(*s, 1);
    }
    Basic.advance(*s, 1);

    // En-passant square
    // @note We don't store the square in our position,
    // but the last move. So we deduce what it was here if there's an en-passant square.
    if s[0] != #char "-" {
        row, col := algebraic_to_row_col(s);
        pawnDirection := ifx position.moveIndex == 1 then 1 else -1;
        position.lastMove.sourceCoord = coord(row - pawnDirection, col);
        position.lastMove.targetCoord = coord(row + pawnDirection, col);
        Basic.advance(*s, 3);
    } else {
        Basic.advance(*s, 2);
    }

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

position_to_fen :: (position : Position) -> string {
    builder : Basic.String_Builder;

    // The board
    for oppositeRow : 0..7 {
        emptyCount := 0;
        for col : 0..7 {
            squareCoord := coord(7 - cast(u8) oppositeRow, cast(u8) col);
            if position.board[squareCoord].kind == .None {
                emptyCount += 1;
            } else {
                if emptyCount != 0 {
                    Basic.print_to_builder(*builder, "%", emptyCount);
                    emptyCount = 0;
                }
                Basic.append(*builder, fen_piece_to_string(position.board[squareCoord]));
            }
        }

        if emptyCount != 0 {
            Basic.print_to_builder(*builder, "%", emptyCount);
            emptyCount = 0;
        }
        if oppositeRow != 7 then Basic.append(*builder, "/");
    }

    // Color to play
    Basic.append(*builder, ifx position_color_to_play(*position) == .White then " w" else " b");

    // Castling rights
    Basic.append(*builder, " ");
    if position.flags & .CastlingAllowedMask {
        if position.flags & .WhiteKingsideCastlingAllowed then Basic.append(*builder, "K");
        if position.flags & .WhiteQueensideCastlingAllowed then Basic.append(*builder, "Q");
        if position.flags & .BlackKingsideCastlingAllowed then Basic.append(*builder, "k");
        if position.flags & .BlackQueensideCastlingAllowed then Basic.append(*builder, "q");
    } else {
        Basic.append(*builder, "-");
    }

    // En-passant square
    enPassantCoord := position_en_passant_coord(*position);
    Basic.append(*builder, " ");
    Basic.append(*builder, ifx enPassantCoord != 0xFF then coord_to_algebraic(enPassantCoord) else "-");

    // @todo Halfmove clock for the 50 move rule
    Basic.append(*builder, " 0");

    // Fullmove number
    Basic.print_to_builder(*builder, " %", (position.moveIndex + 2) / 2);

    return Basic.builder_to_string(*builder);
}

fen_castling_to_position_flag :: (c : u8) -> PositionFlags {
    if c == #char "K" then return .WhiteKingsideCastlingAllowed;
    if c == #char "Q" then return .WhiteQueensideCastlingAllowed;
    if c == #char "k" then return .BlackKingsideCastlingAllowed;
    if c == #char "q" then return .BlackQueensideCastlingAllowed;
    return .None;
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
    return "";
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
    return .{ kind = .None };
}
