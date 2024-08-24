GameView :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    listener : Sill.ListenerComponent;
    ui : Sill.UiComponent;
    // tab : TabComponent;

    textCursor : TextCursorEntity;

    game : *Game;
}

TextCursorEntity :: struct {
    using #as entity : Sill.Entity; @Sill:NoStorage
    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
}

game_view_init :: (game : *Game) {
    gameView := SillMeta.create_game_view_entity(instance.engine);
    Sill.listener_on_message(*gameView.listener, _on_message);

    textCursorMesh := Sill.mesh_make_primitive(*gameView.textCursor.mesh);
    create_rect_mesh(1, UiConstants.HeightLine, existingMesh = textCursorMesh);
    textCursorMesh.material = Magma.create_material(instance.shaders.monochrome);
    Sill.entity_set_disabled(*gameView.textCursor, true);
    Magma.material_set_color(textCursorMesh.material, "color", Chamber.vec3.{1, 1, 1});

    game.view = gameView;
    gameView.game = game;
    variation_init(game.mainVariation, game);
}

game_view_reflow :: (using gameView : *GameView) {
    Sill.transform_commit(*gameView.transform);

    extent := game.study.view.tab.page.content.ui.extent;
    if ui.extent.width == extent.width - 2 * UiConstants.PaddingHorizontal then return;

    ui.extent.width = extent.width - 2 * UiConstants.PaddingHorizontal;
    ui.anchor = .TopLeft;

    if gameView.game.mainVariation != null {
        ply := gameView.game.mainVariation.plies[0];
        if ply.parent != null {
            ply_place(ply, propagate = true);
        }
    }
}

#scope_file

_on_message :: (using gameView : *GameView, message : *Message) {
    if message.kind == {
    case .SelectedPlyChanged;
        if message.newPly.parent == gameView then _update_to_current_move(gameView);
    case .PlyCommentEditStarted;
        if instance.currentGame == gameView.game then _show_text_cursor(gameView, true);
    case .PlyCommentEditStopped;
        if instance.currentGame == gameView.game then _show_text_cursor(gameView, false);
    case .PlyTextCursorPositionChanged;
        _update_text_cursor(gameView, gameView.game.ply);
    case .VariationContentChanged;
        if message.variation.plies[0].game == game {
            _update_height(gameView);
        }
    case .CurrentGameChanged;
        // Show the current game in the study view.
        if gameView.game == message.newGame {
            Sill.entity_set_disabled(gameView, false);
            Sill.entity_set_parent(gameView, game.study.view);
            game.study.view.tab.ui = *gameView.ui; // Use us as the UI provider (getting the size for scrolling).
            game_view_reflow(gameView);
        } else {
            Sill.entity_set_disabled(gameView, true);
        }
    }
}

_update_to_current_move :: (using gameView : *GameView) {
    if game.kind == .Puzzle {
        _update_to_current_move_as_puzzle(gameView);
        return;
    }

    // Uncollapse the tree if needed
    // @todo have it dynamic and hide it back when leaving?
    if game.ply != null {
        topUncollapsedVariation : *VariationEntity;
        variation := game.ply.parentVariation;
        while variation != null {
            if variation.collapsed {
                variation.collapsed = false;
                topUncollapsedVariation = variation;
            }
            variation = ifx variation.parentPly != null then variation.parentPly.parentVariation else null;
        }

        if topUncollapsedVariation != null {
            ply_place(topUncollapsedVariation.plies[0], propagate = true);
        }
    }

    plyY := 0.0;
    plyHeight := 0.0;
    if game.ply != null {
        plyY = game.ply.transform.translation.y;
        plyHeight = game.ply.ui.extent.height;
    }

    // We need to fit the ply at the screen. To do so, either move the gameView down or up
    // given which side is the closest. This makes navigating the moves downwards more
    // natural by having them appearing at the bottom.
    deltaToFitAtTop := 0 - (game.study.view.transform.translation.y + plyY);
    deltaToFitAtBottom := game.study.view.tab.page.content.ui.extent.height - (game.study.view.transform.translation.y + plyY + plyHeight);

    // Clever scrolling, don't scroll if all the node is already visible
    if deltaToFitAtTop <= 0 && deltaToFitAtBottom >= 0 {
        return;
    }

    delta := ifx Math.abs(deltaToFitAtTop) < Math.abs(deltaToFitAtBottom) then deltaToFitAtTop else deltaToFitAtBottom;
    tab_scroll(*game.study.view.tab, delta);
}

_update_to_current_move_as_puzzle :: (using gameView : *GameView) {
    // Uncollapse the tree if needed
    // @todo have it dynamic and hide it back when leaving?
    if game.ply != null {
        ply_place(game.ply, propagate = true);
    }
}

_update_text_cursor :: (using gameView : *GameView, ply : *PlyEntity) {
    Sill.entity_set_parent(*textCursor, ply);

    // @note We always update the cursor, because when the text changed and not the cursor position,
    // the justification of the line might slightly move the cursor itself.
    textCursor.transform.translation = ply.commentMeshNode.transform.translation;
    textCursor.transform.translation.y += UiConstants.HeightLine / 2;
    if ply.textCursorPosition == 0 {
        if ply.charInfos.infos.count != 0 {
            textCursor.transform.translation.x += ply.charInfos.infos[0].effective.xStart;
            textCursor.transform.translation.y += ply.charInfos.infos[0].effective.yStart;
        }
    } else {
        byteIndex : u32;
        for *charInfo : ply.charInfos.infos {
            byteIndex += Chamber.utf8_word_length_after_byte(ply.position.comment, byteIndex);

            if ply.textCursorPosition <= byteIndex {
                textCursor.transform.translation.x += Math.floor(charInfo.effective.xEndWithAdvance + 0.5);
                textCursor.transform.translation.y += charInfo.effective.yStart;
                break;
            }
        }
    }

    Sill.transform_commit(*textCursor.transform);
}

_update_height :: (using gameView : *GameView) {
    // Recompute the size of the game view by finding the last ply.
    ply := Basic.peek(game.mainVariation.plies);
    while ply.variations.count != 0 {
        ply = Basic.peek(Basic.peek(ply.variations).plies);
    }
    ui.extent.height = ply.transform.translation.y + ply.ui.extent.height;
}

_show_text_cursor :: (using gameView : *GameView, show := true) {
    Sill.entity_set_disabled(*textCursor, !show);

    if (show) {
        _update_text_cursor(gameView, gameView.game.ply);
    }
}
