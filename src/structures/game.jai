/* A "Game" can be understood as a collections of variations starting from one position. */
Game :: struct {
    mainVariation : Variation;

    boardOrientation : Color;
    result : Result;
    pgnFileName : string;

    node : *Variation.Node; // Current node.

    // @note In order to never invalidate pointers but still
    // have efficient memory layout, we use pools.
    nodePool : Bucket_Array.Bucket_Array(Variation.Node, 128);
    variationPool : Bucket_Array.Bucket_Array(Variation, 32);

    Result :: enum {
        Unknown :: 0;
        WhiteWin;
        BlackWin;
        Draw;
    }
}

Variation :: struct {
    // @note nodes[0].position is the initial position.
    // And it should not get any variation in it.
    nodes : [..]*Node; // @note Do not flatten this, the struct might be needed for extra info about a variation.

    parentNode : *Node; // Can be null for the main variation.
    index : u16; // Index of the variation in the parent node.

    depth : u16;

    // @todo Rename ply?
    Node :: struct {
        position : Position;
        variations : [..]*Variation;
        comment : string;

        parentVariation : *Variation;
        index : u16; // Index of the node in the parent variation.

        using listData : ListNodeData;
    }
}

game_cleanup :: (game : *Game) {
    Bucket_Array.bucket_array_reset(*game.nodePool);
    Bucket_Array.bucket_array_reset(*game.variationPool);

    variation_cleanup(*game.mainVariation);
    Basic.free(game.pgnFileName);

    (<<game) = .{};
}

variation_cleanup :: (variation : *Variation) {
    for node : variation.nodes {
        node_cleanup(node);
    }
    Basic.array_free(variation.nodes);
}

node_cleanup :: (node : *Variation.Node) {
    Basic.free(node.comment);
    for variation : node.variations {
        variation_cleanup(variation);
    }
    Basic.array_free(node.variations);
}

game_add_variation :: (game : *Game, parentNode : *Variation.Node) -> *Variation {
    variation := Bucket_Array.find_and_occupy_empty_slot(*game.variationPool);
    Basic.array_add(*parentNode.variations, variation);

    variation.parentNode = parentNode;
    variation.index = cast(u16) (parentNode.variations.count - 1);
    variation.depth = parentNode.parentVariation.depth + 1;
    return variation;
}

game_add_variation_node :: (game : *Game, parentVariation : *Variation) -> *Variation.Node {
    node := Bucket_Array.find_and_occupy_empty_slot(*game.nodePool);
    Basic.array_add(*parentVariation.nodes, node);

    node.parentVariation = parentVariation;
    node.index = cast(u16) (parentVariation.nodes.count - 1);
    return node;
}

game_update_to :: (game : *Game, node : *Variation.Node) {
    game.node = node;

    variation := game_current_variation(game);
    board_orient(game.boardOrientation);
    board_update_to_position(node.position);
    list_update_to_current_move(game);
}

game_current_variation :: (game : *Game) -> *Variation {
    return game.node.parentVariation;
}

game_go_to_first_ply :: (game : *Game) {
    game_update_to(game, game.node.parentVariation.nodes[0]);
}

game_go_to_last_ply :: (game : *Game) {
    game_update_to(game, Basic.peek(game.node.parentVariation.nodes));
}

game_go_to_previous_move :: (game : *Game) {
    variation := game_current_variation(game);

    if game.node.index == 0 {
        if game.node.parentVariation == *game.mainVariation then return;
        game_go_to_previous_variation(game);
        game_go_to_previous_move(game);
        game_go_to_previous_move(game);
        return;
    }

    game_update_to(game, game.node.parentVariation.nodes[game.node.index - 1]);
}

game_go_to_next_move :: (game : *Game) {
    if game.node.index == game.node.parentVariation.nodes.count - 1 then return;
    game_update_to(game, game.node.parentVariation.nodes[game.node.index + 1]);
}

game_go_to_previous_variation :: (game : *Game) {
    variation := game.node.parentVariation;
    variationParentNode := variation.parentNode;
    if variationParentNode != null {
        if variation.index > 0 {
            game_update_to(game, variationParentNode.variations[variation.index - 1].nodes[1]);
        } else {
            game_update_to(game, variationParentNode);
        }
    }
}

game_go_to_next_variation :: (game : *Game) {
    // Is there a subvariation from where we are?
    if game.node.variations.count != 0 {
        game_update_to(game, game.node.variations[0].nodes[1]);
    }
    // Or is there a next variation in the parent one?
    else {
        variation := game.node.parentVariation;
        variationParentNode := game.node.parentVariation.parentNode;
        if variationParentNode != null {
            if variation.index < variationParentNode.variations.count - 1 {
                game_update_to(game, variationParentNode.variations[variation.index + 1].nodes[1]);
            }
        }
    }
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

variation_debug_dump :: (variation : Variation, depth : u8) {
    prefix := "| | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | ";
    prefix.count = depth * 2;

    for node, nodeIndex : variation.nodes {
        if nodeIndex == 0 {
            prefix.count -= 1;
            Chamber.debug(prefix, "> {", node.comment, "}");
            prefix.count += 1;
        } else {
            fullMoveIndex := (node.position.moveIndex + 1) / 2;
            Chamber.debug(prefix, fullMoveIndex, ifx node.position.moveIndex % 2 then ". " else "… ", position_last_move_to_san(node.position), " {", node.comment, "}");
        }

        for variation : node.variations {
            variation_debug_dump(<<variation, depth + 1);
        }
    }
}
