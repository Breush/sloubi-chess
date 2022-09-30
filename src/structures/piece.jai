// @note With bit fields, this could be reduced down to 8 bits, thus storing boards nicely
Piece :: struct {
    using kind : PieceKind;
    color : Color;
}

operator== :: (piece1 : Piece, piece2 : Piece) -> bool {
    return piece1.kind == piece2.kind &&
           (piece1.kind == .Empty || piece1.color == piece2.color);
}

PieceKind :: enum u8 {
    Empty :: 0;
    Bishop; B :: Bishop;
    King;   K :: King;
    Knight; N :: Knight;
    Pawn;   P :: Pawn;
    Queen;  Q :: Queen;
    Rook;   R :: Rook;
}

PieceKindCount :: 7;

// Empty :: 0;
// WB; WK; WN; WP; WQ; WR;
// BB; BK; BN; BP; BQ; BR;
PieceId :: u8;
PieceIdCount : PieceId : 13;

make_piece :: (kind : PieceKind, color : Color) -> Piece {
    piece : Piece = ---;
    piece.kind = kind;
    piece.color = color;
    return piece;
}

piece_id :: (piece : Piece) -> PieceId {
    if (piece.kind == .Empty) return 0;
    return 6 * cast(u8) piece.color + cast(u8) piece.kind;
}

piece_id :: (kind : PieceKind, color : Color) -> PieceId {
    if (kind == .Empty) return 0;
    return 6 * cast(u8) color + cast(u8) kind;
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

piece_to_symbol :: (piece : Piece) -> string {
    if piece.kind == .B then return "♝";
    if piece.kind == .K then return "♚";
    if piece.kind == .N then return "♞";
    if piece.kind == .P then return "";
    if piece.kind == .Q then return "♛";
    if piece.kind == .R then return "♜";
    return "?";
}

piece_to_algebraic :: (pieceKind : PieceKind) -> string {
    if pieceKind == .B then return "B";
    if pieceKind == .K then return "K";
    if pieceKind == .N then return "N";
    if pieceKind == .P then return "";
    if pieceKind == .Q then return "Q";
    if pieceKind == .R then return "R";
    return "?";
}

piece_to_algebraic :: (piece : Piece) -> string {
    return piece_to_algebraic(piece.kind);
}

piece_at_coord :: (coord : Coord) -> Piece {
    if instance.game.ply == null then return .{}; // Empty
    return instance.game.ply.position.board[coord];
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
