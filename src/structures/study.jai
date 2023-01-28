// A study is a collection of games.
// It is basically a PGN file.
Study :: struct {
    view : *StudyView; @NoSerialize
    bytes : string; @NoSerialize // File content, holding the data.
    games : [..]Game;
    temporaryGames : [..]Game; @NoSerialize
    computeFlags : ComputeFlags;
    infoFlags : InfoFlags;
    title : string;

    currentGame : *Game; @NoSerialize
    hasUnsavedModifications : bool; @NoSerialize
    hasOutdatedBytes : bool; @NoSerialize

    InfoFlags :: enum_flags u8 {
        MultipleGames;
    }

    // What knowledge we have/want about the study.
    // This knowledge is serialized and can be trusted.
    // It allows us to not reload a file if we only need some global knowledge about it.
    ComputeFlags :: enum_flags u8 {
        Info;           // infoFlags are valid
        GamesTitles;    // games[].title are valid
        GamesBytes;     // games[].bytes are valid
    }
}

load_study :: (filename : string, computeFlags : Study.ComputeFlags = 0) -> *Study {
    study := Hash.table_find_pointer(*instance.studies, filename);
    if study == null {
        study = Hash.table_add(*instance.studies, Basic.copy_string(filename), .{});
    }

    if study.title.count == 0 {
        study.title = Basic.copy_string(String.path_strip_extension(String.path_filename(filename)));
    }

    // The study has already enough computed, no need to recompute anything.
    if computeFlags == 0 || study.computeFlags & computeFlags then return study;

    if study.bytes.count == 0 {
        study.bytes = File.read_entire_file(filename);
        if study.bytes.count == 0 then return null;
    }

    if computeFlags & .GamesTitles || computeFlags & .GamesBytes {
        _refresh_games_and_info_from_bytes(study);
    } else {
        _refresh_info_from_bytes(study);
    }

    return study;
}

study_cleanup :: (using study : *Study) {
    for *game : games {
        game_cleanup(game);
    }

    Basic.array_reset(*games);
    Basic.free(title);
    Basic.free(bytes);
}

study_show_game :: (study : *Study, gameIndex : u32) {
    game := *study.games[gameIndex];
    study_show_game(study, game);
}

study_show_game :: (study : *Study, game : *Game) {
    if study.view == null {
        study.view = study_view_create(study);
    }

    study.currentGame = game;
    if game.view == null then game_create(game);

    send(.StudyCurrentGameChanged, study);
    send(.SelectTab, study.view);
}

study_add_game :: (study : *Study) {
    game := Basic.array_add(*study.temporaryGames);
    game.study = study;

    for *game : study.temporaryGames {
        if game.view != null then game.view.game = game;
    }

    game_setup_main_variation(game);
    rootPly := variation_add_ply(game.mainVariation);
    rootPly.position = get_starting_position();

    send(.StudyGamesChanged, study);
    study_show_game(study, game);
}

study_close :: (study : *Study) {
    if study.view == null then return;

    if study.hasOutdatedBytes {
        Basic.free(study.bytes);
        study.bytes.count = 0;
        study.computeFlags &= ~.GamesBytes;
    }

    for *game : study.games {
        if study.hasOutdatedBytes {
            game.bytes.count = 0;
            if game.mainVariation != null then game.computeFlags &= ~.Summary;
        }
        game_close(game);
    }

    Sill.destroy_entity(study.view);
    study.view = null;
    study.hasOutdatedBytes = false;
}

study_save :: (using study : *Study) {
    hasUnsavedModifications = false;
    send(.StudyUnsavedModificationsChanged, study);

    // Transfer temporary games to the main games array.
    if temporaryGames.count != 0 {
        for *game : temporaryGames {
            Basic.array_add(*games, <<game);
        }
        temporaryGames.count = 0;
        for *game : games {
            if game.view != null then game.view.game = game;
        }
    }

    Basic.push_allocator(Basic.temp);
    Basic.auto_release_temp();

    // Find the study filename.
    filename : string;
    for *it, studyFilename : instance.studies {
        if it == study {
            filename = studyFilename;
            break;
        }
    }
    if filename.count == 0 then return;

    Basic.log("Saving study as PGN file %.", filename);

    sb : Basic.String_Builder;
    for *game, gameIndex : games {
        write_pgn(*sb, game);
        if gameIndex != games.count - 1 {
            Basic.append(*sb, "\n");
        }
    }
    File.write_entire_file(filename, *sb);

    hasOutdatedBytes = true;
}

study_mark_unsaved_modifications :: (using study : *Study) {
    hasUnsavedModifications = true;
    send(.StudyUnsavedModificationsChanged, study);
}

#scope_file

_refresh_info_from_bytes :: (study : *Study) {
    study.computeFlags |= .Info;

    bytes := study.bytes;
    skip_bom(*bytes);
    skip_blanks(*bytes);

    // First tags.
    while bytes[0] == #char "[" {
        skip_until(*bytes, #char "\n");
        skip_blanks(*bytes);
    }

    // Try to find the next game, don't match [ in comments
    while true {
        skip_until(*bytes, #char "\n");
        skip_blanks(*bytes);

        if bytes.count == 0 then break;
        if bytes[0] == #char "[" && bytes[1] != #char "%" then break;
    }

    if bytes.count > 0 && bytes[0] == #char "[" {
        study.infoFlags |= .MultipleGames;
    }
}

// Reading a PGN file and split it at each game.
// This should be pretty fast.
_refresh_games_and_info_from_bytes :: (study : *Study) {
    study.computeFlags |= Study.ComputeFlags.Info | .GamesTitles | .GamesBytes;

    bytes := study.bytes;
    skip_bom(*bytes);
    skip_blanks(*bytes);

    gameIndex := 0;
    while bytes.count > 0 {
        tags : [7]string;

        game : *Game;
        if gameIndex >= study.games.count then game = Basic.array_add(*study.games);
        else game = *study.games[gameIndex];
        game.bytes = bytes;
        game.study = study;

        // Skip until no more tags.
        while bytes[0] == #char "[" {
            Basic.advance(*bytes);
            tagName := parse_word(*bytes);
            Basic.advance(*bytes);
            Basic.advance(*bytes); // Skipping the quote.

            if tagName == "Event" then tags[0] = parse_until(*bytes, .[ #char "\"" ]);
            else if tagName == "Site" then tags[1] = parse_until(*bytes, .[ #char "\"" ]);
            else if tagName == "Date" then tags[2] = parse_until(*bytes, .[ #char "\"" ]);
            else if tagName == "Round" then tags[3] = parse_until(*bytes, .[ #char "\"" ]);
            else if tagName == "White" then tags[4] = parse_until(*bytes, .[ #char "\"" ]);
            else if tagName == "Black" then tags[5] = parse_until(*bytes, .[ #char "\"" ]);
            else if tagName == "Result" then tags[6] = parse_until(*bytes, .[ #char "\"" ]);

            skip_until(*bytes, #char "\n");
            skip_blanks(*bytes);
        }

        // Try to find the next game, don't match [ in comments
        while true {
            skip_until(*bytes, #char "\n");
            skip_blanks(*bytes);

            if bytes.count == 0 then break;
            if bytes[0] == #char "[" && bytes[1] != #char "%" then break;
        }

        game.bytes.count = game.bytes.count - bytes.count;

        if game.title.count == 0 {
            game.title = Basic.sprint(instance.config.library.gameTitleFormat, tags[0], tags[1], tags[2], tags[3], tags[4], tags[5], tags[6]);
        }

        gameIndex += 1;
    }

    if study.games.count > 1 then study.infoFlags |= .MultipleGames;
}
