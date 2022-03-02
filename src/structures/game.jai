/* A "Game" can be understood as a collections of variants starting from one position. */
Game :: struct {
    mainVariant : Variant;

    boardOrientation : Color;

    variantIndices : [..]VariantIndex; // Indices to go to the current variant.
    nodeIndex : u16;                   // Current node index in the variant described above.
}

Variant :: struct {
    // @note nodes[0].position is the initial position.
    // And it should not get any variant in it.
    nodes : [..]Node; // @note Do not flatten this, the struct might be needed for extra info about a variant.

    Node :: struct {
        position : Position;
        variants : [..]Variant;
        comment : string;

        using varienterData : VarianterNodeData;
    }
}

VariantIndex :: struct {
    nodeIndex : u16;
    index : u16;
}

game_update_to :: (game : *Game, nodeIndex : u16) {
    game.nodeIndex = nodeIndex;

    variant := game_current_variant(game);
    board_orient(game.boardOrientation);
    board_update_to_position(variant.nodes[nodeIndex].position);
    varianter_update_to_current_move(game);
}

game_current_variant :: (game : *Game) -> *Variant {
    variant := *game.mainVariant;

    for variantIndex : game.variantIndices {
        variant = *variant.nodes[variantIndex.nodeIndex].variants[variantIndex.index];
    }

    return variant;
}

game_current_variant_parent_node :: (game : *Game) -> *Variant.Node {
    node : *Variant.Node;

    variant := *game.mainVariant;
    for variantIndex : game.variantIndices {
        node = *variant.nodes[variantIndex.nodeIndex];
        variant = *node.variants[variantIndex.index];
    }

    return node;
}

game_go_to_first_ply :: (game : *Game) {
    game_update_to(game, 0);
}

game_go_to_last_ply :: (game : *Game) {
    variation := game_current_variant(game);
    game_update_to(game, cast(u16) variation.nodes.count - 1);
}

game_go_to_previous_move :: (game : *Game) {
    variant := game_current_variant(game);

    if game.nodeIndex == 0 {
        if game.variantIndices.count == 0 then return;
        game_go_to_previous_variation(game);
        game_go_to_previous_move(game);
        game_go_to_previous_move(game);
        return;
    }

    game_update_to(game, game.nodeIndex - 1);
}

game_go_to_next_move :: (game : *Game) {
    variant := game_current_variant(game);
    if game.nodeIndex == variant.nodes.count - 1 then return;
    game_update_to(game, game.nodeIndex + 1);
}

game_go_to_previous_variation :: (game : *Game) {
    variant := game_current_variant(game);

    variantParentNode := game_current_variant_parent_node(game);
    if variantParentNode != null {
        variantIndex := Basic.peek_pointer(game.variantIndices);
        if variantIndex.index > 0 {
            variantIndex.index -= 1;

            game.nodeIndex = 0;
            game_go_to_next_move(game);
        } else {
            game.nodeIndex = Basic.peek(game.variantIndices).nodeIndex;
            Basic.array_resize(*game.variantIndices, game.variantIndices.count - 1);
            game_update_to(game, game.nodeIndex);
        }
    }
}

game_go_to_next_variation :: (game : *Game) {
    variant := game_current_variant(game);

    // Is there a subvariant from where we are?
    if variant.nodes[game.nodeIndex].variants.count != 0 {
        variantIndex : VariantIndex;
        variantIndex.nodeIndex = game.nodeIndex;
        variantIndex.index = 0;
        Basic.array_add(*game.variantIndices, variantIndex);

        game.nodeIndex = 0;
        game_go_to_next_move(game);
    }
    // Or is there a next variant in the parent one?
    else {
        // @todo Decide on how to navigate variants by keyboard.
        variantParentNode := game_current_variant_parent_node(game);
        if variantParentNode != null {
            variantIndex := Basic.peek_pointer(game.variantIndices);
            if variantIndex.index < variantParentNode.variants.count - 1 {
                variantIndex.index += 1;

                game.nodeIndex = 0;
                game_go_to_next_move(game);
            }
        }
    }
}

game_debug_dump :: (game : Game) {
    variant_debug_dump(game.mainVariant, 0);
}

variant_debug_dump :: (variant : Variant, depth : u8) {
    prefix := "| | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | ";
    prefix.count = depth * 2;

    for node, nodeIndex : variant.nodes {
        if nodeIndex == 0 {
            prefix.count -= 1;
            Chamber.debug(prefix, "> {", node.comment, "}");
            prefix.count += 1;
        } else {
            fullMoveIndex := (node.position.moveIndex + 1) / 2;
            Chamber.debug(prefix, fullMoveIndex, ifx node.position.moveIndex % 2 then ". " else "... ", position_last_move_to_san(node.position), " {", node.comment, "}");
        }

        for variant : node.variants {
            variant_debug_dump(variant, depth + 1);
        }
    }
}
