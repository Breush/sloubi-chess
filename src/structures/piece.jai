// @note With bit fields, this could be reduced down to 8 bits, thus storing boards nicely
Piece :: struct {
    using kind : PieceKind;
    color : Color;
}

Color :: enum u8 {
    White :: 0;
    Black;
}

operator== :: (piece1 : Piece, piece2 : Piece) -> bool {
    return piece1.kind == piece2.kind &&
           (piece1.kind == .None || piece1.color == piece2.color);
}

PieceKind :: enum u8 {
    None :: 0;
    Bishop; B :: Bishop;
    King;   K :: King;
    Knight; N :: Knight;
    Pawn;   P :: Pawn;
    Queen;  Q :: Queen;
    Rook;   R :: Rook;
}

PieceKindCount :: 7;

// None :: 0;
// WB; WK; WN; WP; WQ; WR;
// BB; BK; BN; BP; BQ; BR;
PieceId :: u8;
PieceIdCount : PieceId : 13;

make_piece :: (kind : PieceKind, color : Color) -> Piece {
    return .{ kind, color };
}

piece_id :: (piece : Piece) -> PieceId {
    if piece.kind == .None then return 0;
    return 6 * cast(u8) piece.color + cast(u8) piece.kind;
}

piece_id :: (kind : PieceKind, color : Color) -> PieceId {
    if kind == .None then return 0;
    return 6 * cast(u8) color + cast(u8) kind;
}

piece_from_piece_id :: (pieceId : PieceId) -> Piece {
    if pieceId == 0 then return .{};
    return make_piece(cast(PieceKind) ((pieceId - 1) % 6 + 1), cast(Color) ((pieceId - 1) / 6));
}

piece_to_utf8 :: (piece : Piece) -> string {
    if piece.kind == .B && piece.color == .Black then return "♝";
    if piece.kind == .K && piece.color == .Black then return "♚";
    if piece.kind == .N && piece.color == .Black then return "♞";
    if piece.kind == .P && piece.color == .Black then return "♟";
    if piece.kind == .Q && piece.color == .Black then return "♛";
    if piece.kind == .R && piece.color == .Black then return "♜";
    if piece.kind == .B && piece.color == .White then return "♗";
    if piece.kind == .K && piece.color == .White then return "♔";
    if piece.kind == .N && piece.color == .White then return "♘";
    if piece.kind == .P && piece.color == .White then return "♙";
    if piece.kind == .Q && piece.color == .White then return "♕";
    if piece.kind == .R && piece.color == .White then return "♖";
    return " ";
}

piece_kind_to_symbol :: (pieceKind : PieceKind) -> string {
    if pieceKind == .P then return "";
    if pieceKind == .R then return instance.config.env.piecesSymbols[0];
    if pieceKind == .N then return instance.config.env.piecesSymbols[1];
    if pieceKind == .B then return instance.config.env.piecesSymbols[2];
    if pieceKind == .Q then return instance.config.env.piecesSymbols[3];
    if pieceKind == .K then return instance.config.env.piecesSymbols[4];
    return "?";
}

piece_at_coord :: (coord : Coord) -> Piece {
    if instance.currentGame == null then return .{}; // Empty
    return instance.currentGame.ply.position.board[coord];
}

// In centipawns
piece_kind_value :: (pieceKind : PieceKind) -> s32 {
    if pieceKind == .P then return 100;
    if pieceKind == .R then return 500;
    if pieceKind == .N then return 300;
    if pieceKind == .B then return 350;
    if pieceKind == .Q then return 900;
    if pieceKind == .K then return 0x7FFF_FFFF;
    return 0;
}

PieceMovement :: struct {
    range : u8;
    directions : [][2]s8;
}

PIECES_MOVEMENT :: PieceMovement.[
    /* .Empty */  PieceMovement.{},
    /* .Bishop */ PieceMovement.{ range = 8, directions = .[.[1, 1], .[1, -1], .[-1, 1], .[-1, -1]] },
    /* .King */   PieceMovement.{ range = 1, directions = .[.[1, 1], .[1, -1], .[-1, 1], .[-1, -1], .[1, 0], .[0, 1], .[0, -1], .[-1, 0]] },
    /* .Knight */ PieceMovement.{ range = 1, directions = .[.[1, 2], .[2, 1], .[-2, 1], .[-1, 2], .[-1, -2], .[-2, -1], .[2, -1], .[1, -2]] },
    /* .Pawn */   PieceMovement.{},
    /* .Queen */  PieceMovement.{ range = 8, directions = .[.[1, 1], .[1, -1], .[-1, 1], .[-1, -1], .[1, 0], .[0, 1], .[0, -1], .[-1, 0]] },
    /* .Rook */   PieceMovement.{ range = 8, directions = .[.[1, 0], .[0, 1], .[-1, 0], .[0, -1]] },
];
