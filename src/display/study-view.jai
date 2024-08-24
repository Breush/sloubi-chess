StudyView :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    listener : Sill.ListenerComponent;
    ui : Sill.UiComponent;
    tab : TabComponent;

    study : *Study;

    gameEditInitialBoardPosition : CompactBoardPosition;
}

study_view_create :: (study : *Study) -> *StudyView {
    studyView := SillMeta.create_study_view_entity(instance.engine);
    Sill.listener_on_message(*studyView.listener, _on_message);
    studyView.study = study;

    studyView.tab.text = study.title;
    studyView.tab.icon = ifx study.infoFlags & .MultipleGames then ForkAwesome.Book else ForkAwesome.Gamepad;
    studyView.tab.onReflow = xx _on_reflow;
    Basic.array_add(*studyView.tab.actions, .{ "Close study", ForkAwesome.WindowCloseO, xx _on_close, .Right });
    Basic.array_add(*studyView.tab.actions, .{ "Save as PGN", ForkAwesome.FloppyO, xx _on_save, .None });
    Basic.array_add(*studyView.tab.actions, .{ "Open external analysis", ForkAwesome.Laptop, xx _on_open_external_analysis, .Right });
    Basic.array_add(*studyView.tab.actions, .{ "Edit game", ForkAwesome.Pencil, xx _on_edit_game, .Right });
    Basic.array_add(*studyView.tab.actions, .{ "Create new game", ForkAwesome.Plus, xx _on_create_new_game, .Left });
    tab_commit_text(*studyView.tab);
    tab_commit_actions(*studyView.tab);

    studyView.tab.menu.onItemClick = xx _on_menu_item_click;
    _refresh_games_list(studyView);
    _on_reflow(studyView);

    Sill.transform_commit(*studyView.transform);

    return studyView;
}

#scope_file

_on_message :: (using studyView : *StudyView, message : *Message) {
    if message.kind == {
    case .StudyCurrentGameChanged;
        if study == message.study {
            for *game, gameIndex : study.games {
                if game == study.currentGame then tab.menu.selectedItemIndex = cast(u32) gameIndex;
            }
            for *game, gameIndex : study.temporaryGames {
                if game == study.currentGame then tab.menu.selectedItemIndex = cast(u32) (study.games.count + gameIndex);
            }
            tab_commit_menu(*tab);
        }
    case .StudyGamesChanged;
        if study == message.study {
            _refresh_games_list(studyView);
        }
    case .StudyUnsavedModificationsChanged;
        if study == message.study {
            tab.actions[1].place = ifx study.hasUnsavedModifications then TabComponent.Action.Place.Right else .None;
            tab_commit_actions(*tab);
        }
    case .PositionBoardChanged; #through;
    case .PositionBoardCoordChanged;
        if study.currentGame == instance.currentGame {
            study.currentGame.ply.customPosition = true;
            study_mark_unsaved_modifications(study);
        }
    case .ModeChanged;
        if message.oldMode == .GameEdit then _stop_game_edit();
    }
}

_on_reflow :: (using studyView : *StudyView) {
    for *game : study.games {
        if game.view == null then continue;
        game_view_reflow(game.view);
    }
}

_refresh_games_list :: (using studyView : *StudyView) {
    Basic.array_resize(*tab.menu.items, study.games.count + study.temporaryGames.count);
    for *game, gameIndex : study.games {
        tab.menu.items[gameIndex] = game.title;
    }
    for *game, gameIndex : study.temporaryGames {
        tab.menu.items[study.games.count + gameIndex] = game.title;
    }
    tab_commit_menu(*tab);
}

_on_menu_item_click :: (using studyView : *StudyView, itemIndex : u32) {
    if itemIndex >= study.games.count {
        study_show_game(study, *study.temporaryGames[itemIndex - study.games.count]);
    } else {
        study_show_game(study, *study.games[itemIndex]);
    }
}

_on_create_new_game :: (using studyView : *StudyView) {
    dialogData : DialogData(Study);
    dialogData.mainText = "Where do you want to add a new game?";
    dialogData.text = "Note that adding a subgame can create unreadable PGNs for other softwares.";
    dialogData.choices = .["Add to study", "Add subgame", "Cancel"];
    dialogData.cancelChoiceIndex = 2;
    dialogData.callback = (dialog : *DialogEntity, choiceIndex : u32, study : *Study) {
        dialog_close(dialog);

        if choiceIndex == 0 {
            study_add_game(study);
        } else if choiceIndex == 1 {
            game_add_subgame(study.currentGame);
        }
    };
    dialogData.userData = study;
    dialog_create(dialogData);
}

_on_close :: (using studyView : *StudyView) {
    if study.hasUnsavedModifications {
        dialogData : DialogData(Study);
        dialogData.mainText = "Do you want to save the changes you made to this study?";
        dialogData.text = "Your changes will be lost if you don't save them.";
        dialogData.choices = .["Save", "Cancel", "Don't save"];
        dialogData.cancelChoiceIndex = 1;
        dialogData.callback = (dialog : *DialogEntity, choiceIndex : u32, study : *Study) {
            dialog_close(dialog);

            if choiceIndex == 0 {
                study_save(study);
                study_close(study);
            } else if choiceIndex == 2 {
                study_close(study);
            }
        };
        dialogData.userData = study;
        dialog_create(dialogData);
    } else {
        study_close(study);
    }
}

_on_open_external_analysis :: (using studyView : *StudyView) {
    Chamber.os_open_browser(Basic.tprint("%1%2", instance.config.analysis.externalSite, position_to_fen(study.currentGame.ply.position)));
}

_on_save :: (using studyView : *StudyView) {
    study_save(study);
}

_on_edit_game :: (using studyView : *StudyView) {
    currentPly := instance.currentGame.ply;
    canEditPosition := (currentPly.index == currentPly.parentVariation.plies.count - 1) ||
                       currentPly.parentVariation.plies[currentPly.index + 1].first;

    if !canEditPosition then board_interactive(*instance.metaBoard.boardView, false);
    else board_position_edit(*instance.metaBoard.boardView, canEditPosition);
    ui_set_focused(*instance.metaBoard.boardView.ui);

    // @note So, we can edit the position on any ply, but we only save Tags to the first ply of a variation.
    // Technically we can have tags anywhere, and they work, but this is harder to express in the UI,
    // and probably not a common case anyway.

    studyView.gameEditInitialBoardPosition = compact_board_position(currentPly.position.board);
    firstPly := game_subgame_first_ply(instance.currentGame);

    elements : [..]DialogFormElement;
    elements.allocator = Basic.temp;

    descriptionText : string;
    if firstPly.index == 0 then descriptionText = "Global game tags:";
    else descriptionText = Basic.tprint("Current subgame tags:", firstPly.index);

    editPositionText : string;
    if canEditPosition then editPositionText = Basic.tprint("Edit the current position:\nFocus the board by clicking on it once, and use %, %, %, %, % or % keys over squares to edit the pieces. Change color or empty a square by pressing a key multiple times.", instance.config.env.piecesMap[0], instance.config.env.piecesMap[1], instance.config.env.piecesMap[2], instance.config.env.piecesMap[3], instance.config.env.piecesMap[4], instance.config.env.piecesMap[5]);
    else editPositionText = "Edit the current position:\nDisabled as this is not the last move of the current variation.";

    Basic.array_add(*elements,
                    .{ kind = .TextEntry, text = "Game title", value = instance.currentGame.title },
                    .{ kind = .Label, text = descriptionText, value = "mainLight", anchor = .Left },
                    .{ kind = .TextEntry, text = "Event", value = game_subgame_tag_or_empty(instance.currentGame, firstPly, .Event).str },
                    .{ kind = .TextEntry, text = "Site",  value = game_subgame_tag_or_empty(instance.currentGame, firstPly, .Site).str },
                    .{ kind = .TextEntry, text = "Date",  value = game_subgame_tag_or_empty(instance.currentGame, firstPly, .Date).str },
                    .{ kind = .TextEntry, text = "Round", value = game_subgame_tag_or_empty(instance.currentGame, firstPly, .Round).str },
                    .{ kind = .TextEntry, text = "White", value = game_subgame_tag_or_empty(instance.currentGame, firstPly, .White).str },
                    .{ kind = .TextEntry, text = "Black", value = game_subgame_tag_or_empty(instance.currentGame, firstPly, .Black).str },
                    // .{ kind = .Button, text = "+", callback = (data : *void) {
                    //     Chamber.debug("Hey");
                    // }},
                    .{ kind = .Label, text = editPositionText, value = "mainLight", anchor = .Left },
                    );
                    // @todo BoardOrientation
                    // @todo NumberEntry for WhiteElo/BlackElo

    dialogFormData : DialogFormData(PlyEntity);
    dialogFormData.anchor = .Half;
    dialogFormData.elements = elements;
    dialogFormData.choices = .[ "Apply & Close", "Cancel" ];
    dialogFormData.cancelChoiceIndex = 1;
    dialogFormData.callback = (dialog : *DialogEntity, choiceIndex : u32, firstPly : *PlyEntity) {
        if choiceIndex == 0 {
            for elementInfo, elementIndex : dialog.content.elementInfos {
                if !elementInfo.changed then continue;
                study_mark_unsaved_modifications(instance.currentGame.study);
                if elementIndex == 0 {
                    Basic.free(instance.currentGame.title);
                    instance.currentGame.title = Basic.copy_string(elementInfo.value);
                    send(.CurrentGameTitleChanged);
                } else {
                    tagName := cast(TagName) (elementIndex - 1);
                    game_subgame_set_tag(instance.currentGame, firstPly, tagName, .{ str = Basic.copy_string(elementInfo.value) });
                }
            }
        } else {
            // Restore previous position.
            instance.currentGame.ply.position.board = board_position(instance.currentGame.study.view.gameEditInitialBoardPosition);
            send(.BoardPositionChanged);
        }

        dialog_close(dialog);
    };
    dialogFormData.userData = firstPly;
    dialogFormData.mode = .GameEdit;
    dialog_form_create(dialogFormData);
}

_stop_game_edit :: () {
    board_interactive(*instance.metaBoard.boardView, true);
    board_position_edit(*instance.metaBoard.boardView, false);
    ui_set_focused(*instance.metaBoard.boardView.ui, false);
}
