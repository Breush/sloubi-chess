/* A "Game" can be understood as a collections of variations starting from one position. */
Game :: struct {
    study : *Study; @NoSerialize
    view : *GameView; @NoSerialize

    mainVariation : *VariationEntity; @NoSerialize
    ply : *PlyEntity; @NoSerialize // Selected ply.

    boardOrientation : Color;
    result : Result;
    tags : struct {
        // PGN standard tags, except Result.
        event : string;
        site : string;
        date : string;
        round : string;
        white : string; // @todo At the end, map to one player in a database.
        black : string;
        // PGN non-standard tags.
        whiteElo : u16;
        blackElo : u16;

        // Other tags, not used internally. @note Not a hash-table to keep order.
        extra : [..]struct { name : string; value : string; };
    } @NoSerialize

    bytes : string; @NoSerialize // View from the bytes array in study, showing one game in PGN format.
    title : string;
    summary : GameSummary;
    computeFlags : ComputeFlags;

    Result :: enum u8 {
        Unknown :: 0;
        WhiteWin;
        BlackWin;
        Draw;
    }

    // What knowledge we have/want about the game.
    ComputeFlags :: enum_flags u8 {
        Summary;    // summary is valid
        Plies;      // mainVariation is valid
    }
}

GameSummary :: struct {
    lastBoardPosition : CompactBoardPosition;
    lastMove : SimpleMove;
}

load_game :: (filename : string, gameIndex : u32, computeFlags : Game.ComputeFlags = 0) -> *Game {
    study := load_study(filename);

    // @note We try not to load the GamesBytes if we don't need to,
    // therefore we just look as if the study exists and has a valid summary for the game first.
    if study == null then return null;
    if study.games.count > gameIndex && study.games[gameIndex].computeFlags & computeFlags then return *study.games[gameIndex];

    game : *Game;
    if study.games.count > gameIndex then game = *study.games[gameIndex];

    // Load the bytes and the PGN only if the game is not already in memory.
    if game == null || game.mainVariation == null {
        study = load_study(filename, .GamesBytes);
        if study == null || study.games.count <= gameIndex then return null;
        game = *study.games[gameIndex];
        load_pgn(game.bytes, game);
        game.computeFlags |= .Plies;
    }

    if computeFlags == 0 || game.computeFlags & computeFlags then return game;

    if computeFlags & .Summary && !(game.computeFlags & .Summary) {
        _load_game_summary(game);
    }

    return game;
}

game_create :: (game : *Game) {
    if game.mainVariation == null {
        load_pgn(game.bytes, game);
    }

    game.view = game_view_create(game);
    game_show(game);
    game_update_to(game, game.mainVariation.plies[0]);
}

game_close :: (game : *Game) {
    if game == null || game.mainVariation == null then return;

    variation_cleanup(game.mainVariation);
    game.mainVariation = null;

    if game.view != null {
        Sill.destroy_entity(game.view);
        game.view = null;
    }

    if instance.currentGame == game then game_show(null);
}

game_cleanup :: (game : *Game) {
    if game == null then return;

    if game.mainVariation != null {
        variation_cleanup(game.mainVariation);
        game.mainVariation = null;
    }

    Basic.free(game.tags.event);
    Basic.free(game.tags.site);
    Basic.free(game.tags.date);
    Basic.free(game.tags.round);
    Basic.free(game.tags.white);
    Basic.free(game.tags.black);
    for extraTag : game.tags.extra {
        Basic.free(extraTag.name);
        Basic.free(extraTag.value);
    }
    Basic.array_free(game.tags.extra);
    Basic.free(game.title);

    if game.view != null {
        Sill.destroy_entity(game.view);
        game.view = null;
    }

    game_show(null);
}

game_show :: (game : *Game) {
    if (instance.currentGame == game) return;
    instance.currentGame = game;
    send(.CurrentGameChanged);
}

game_setup_main_variation :: (game : *Game) {
    game.mainVariation = SillMeta.create_variation_entity(instance.engine);
}

game_add_variation :: (game : *Game, parentPly : *PlyEntity) -> *VariationEntity {
    variation := SillMeta.create_variation_entity(instance.engine);
    variation.collapsed = instance.config.moves.variationsCollapsed;
    Basic.array_add(*parentPly.variations, variation);

    variation.parentPly = parentPly;
    variation.index = cast(u16) (parentPly.variations.count - 1);
    variation.depth = parentPly.parentVariation.depth + 1;
    return variation;
}

game_update_to :: (game : *Game, ply : *PlyEntity) {
    oldPly := game.ply;
    game.ply = ply;

    send(.SelectedPlyChanged, oldPly);
}

game_go_to_first_ply :: (game : *Game) {
    game_update_to(game, game.ply.parentVariation.plies[0]);
}

game_go_to_last_ply :: (game : *Game) {
    game_update_to(game, Basic.peek(game.ply.parentVariation.plies));
}

game_go_to_previous_move :: (game : *Game) {
    variation := game.ply.parentVariation;

    if game.ply.index == 0 {
        if game.ply.parentVariation == game.mainVariation then return;
        game_go_to_previous_variation(game);
        game_go_to_previous_move(game);
        game_go_to_previous_move(game);
        return;
    }

    game_update_to(game, game.ply.parentVariation.plies[game.ply.index - 1]);
}

game_go_to_next_move :: (game : *Game) {
    if game.ply.index == game.ply.parentVariation.plies.count - 1 then return;
    game_update_to(game, game.ply.parentVariation.plies[game.ply.index + 1]);
}

game_go_to_previous_variation :: (game : *Game) {
    variation := game.ply.parentVariation;
    variationParentPly := variation.parentPly;
    if variationParentPly != null {
        if variation.index > 0 {
            game_update_to(game, variationParentPly.variations[variation.index - 1].plies[1]);
        } else {
            game_update_to(game, variationParentPly);
        }
    }
}

game_go_to_next_variation :: (game : *Game) {
    // Is there a subvariation from where we are?
    if game.ply.variations.count != 0 {
        game_update_to(game, game.ply.variations[0].plies[1]);
    }
    // Or is there a next variation in the parent one?
    else {
        variation := game.ply.parentVariation;
        variationParentPly := game.ply.parentVariation.parentPly;
        if variationParentPly != null {
            if variation.index < variationParentPly.variations.count - 1 {
                game_update_to(game, variationParentPly.variations[variation.index + 1].plies[1]);
            }
        }
    }
}

game_play_move :: (game : *Game, sourceCoord : Coord, targetCoord : Coord, promotionPieceKind : PieceKind) {
    // Check if the move already exists, and if so, just select it
    for nextPly : ply_next_plies(game.ply) {
        if nextPly.position.lastMove.sourceCoord == sourceCoord &&
           nextPly.position.lastMove.targetCoord == targetCoord &&
           (nextPly.position.lastMove.promotionPieceKind == promotionPieceKind) {
            game_update_to(game, nextPly);
            return;
        }
    }

    // The position does not exists yet, so:
    //  - if a next ply already exists, create a new variation
    //  - if there's no next ply, add to the current variation
    variation := game.ply.parentVariation;
    nextPly := ply_next_ply(game.ply);
    if nextPly != null {
        variation = game_add_variation(game, nextPly);
        basePly := variation_add_ply(variation); // @todo Better to just store the starting position within the variation?
        position_copy_state_from(*basePly.position, game.ply.position);
        variation_init(variation);
    }

    ply := variation_add_ply(variation);
    position_copy_state_from(*ply.position, game.ply.position);
    position_play_move(*ply.position, sourceCoord, targetCoord, promotionPieceKind);

    ply_init(ply);
    game_update_to(game, ply);

    // @todo Technically, it would be better to send a message.
    study_mark_unsaved_modifications(game.study);
}

game_edit_ply_comment :: (game : *Game) {
    if game.ply == null then return;
    ply_edit_comment(game.ply);
}

game_result_to_string :: (result : Game.Result) -> string {
    if #complete result == {
        case .Unknown; return "*";
        case .WhiteWin; return "1-0";
        case .BlackWin; return "0-1";
        case .Draw; return "1/2-1/2";
    }
}

game_debug_dump :: (game : Game) {
    variation_debug_dump(game.mainVariation, 0);
}

#scope_file

_load_game_summary :: (game : *Game) {
    game.computeFlags |= .Summary;
    game.summary.lastBoardPosition = compact_board_position(Basic.peek(game.mainVariation.plies).position.board);
    game.summary.lastMove = Basic.peek(game.mainVariation.plies).position.lastMove;
}
