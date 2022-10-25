/* A "Game" can be understood as a collections of variations starting from one position. */
Game :: struct {
    mainVariation : *VariationEntity;

    boardOrientation : Color;
    result : Result;
    pgnFileName : string;
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
    }

    ply : *PlyEntity; // Selected ply.

    Result :: enum {
        Unknown :: 0;
        WhiteWin;
        BlackWin;
        Draw;
    }
}

game_show :: (game : *Game) {
    send(.ModeGameStarted);
    game_update_to(game, game.mainVariation.plies[0]);
}

game_cleanup :: (game : *Game) {
    send(.ModeGameStopped);

    game.ply = null;
    if game.mainVariation != null then variation_cleanup(game.mainVariation);

    Basic.free(game.pgnFileName);
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

    (<<game) = .{};
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

    send(.GameSelectedPlyChanged, oldPly);
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
