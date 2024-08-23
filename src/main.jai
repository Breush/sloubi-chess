// #import "Basic"()(MEMORY_DEBUGGER=true);

Sill :: #import "Sill";
Magma :: Sill.Magma;
Crater :: #import "Crater";
Chamber :: #import "Chamber";

Basic :: #import "Basic";
Debug :: #import "Debug";
Hash :: #import "Hash_Table";
Math :: #import "Math";
File :: #import "File";
Sort :: #import "Sort";
String :: #import "String";
BucketArray :: #import "Bucket_Array";
CommandLine :: #import "Command_Line";
FileUtilities :: #import "File_Utilities";
for_expansion :: Hash.for_expansion;

#load "display/components/button.jai";
#load "display/components/tab.jai";
#load "display/background.jai";
#load "display/board-view.jai";
#load "display/dialog.jai";
#load "display/game-view.jai";
#load "display/label.jai";
#load "display/library.jai";
#load "display/meta-board.jai";
#load "display/sidebar.jai";
#load "display/smart-mover.jai";
#load "display/study-view.jai";
#load "display/text-entry.jai";
#load "display/uci.jai";
#load "helpers/arrow-mesh.jai";
#load "helpers/entities.jai";
#load "helpers/fork-awesome.jai";
#load "helpers/rect-mesh.jai";
#load "helpers/text-mesh.jai";
#load "helpers/tracing-mesh.jai";
#load "helpers/ui-constants.jai";
#load "structures/board.jai";
#load "structures/coord.jai";
#load "structures/game.jai";
#load "structures/piece.jai";
#load "structures/ply.jai";
#load "structures/position.jai";
#load "structures/san-key.jai";
#load "structures/study.jai";
#load "structures/variation.jai";
#load "readers/fen.jai";
#load "readers/pgn.jai";
#load "readers/utils.jai";
#load "config.jai";
#load "controller.jai";
#load "message.jai";

instance : Instance;

Instance :: struct {
    engine : *Sill.Engine(SillMeta);

    shaders : struct {
        decorum : *Magma.Shader;
        gradient : *Magma.Shader;
        monochrome : *Magma.Shader;
        text : *Magma.Shader;
        translucentMonochrome : *Magma.Shader;
    }

    config : Config;
    persistence : Persistence; // @todo Make it BOS, and save it on exit.

    background : *BackgroundEntity;
    controller : *ControllerEntity;
    library : *LibraryEntity;
    metaBoard : *MetaBoardEntity;
    sidebar : *SidebarEntity;
    uci : *UciEntity;

    textMaterialCache : [..]TextMaterialCacheInfo;

    // @fixme Dangling refs to studies can happen.
    studies : Hash.Table(string, Study); // Key is PGN file path.
    currentGame : *Game;

    handlingClosingMainWindow : bool;

    STUDIES_VERSION : u32 : 0x1;
}

TextMaterialCacheInfo :: struct {
    fontTexture : *Magma.Texture;
    color : Chamber.vec3;
    material : *Magma.Material;
}

Arguments :: struct {
    pgn : string;
    gameIndex : u32;
    config := "./assets/config.json";
    noCache : bool;
}

main :: () {
    UA :: #import "Unmapping_Allocator";
    context.allocator = UA.get_unmapping_allocator();

    Debug.init(); // For signal handlers
    Chamber.init_logger();
    context.log_level = .VERBOSE;

    // Make resources relative to the binary, so that it does not depend on from where it is launched.
    {
        Basic.push_allocator(Basic.temp);
        commandLineArguments := Basic.get_command_line_arguments();
        Basic.set_working_directory(String.path_strip_filename(commandLineArguments[0]));
    }

    // @todo Have a better command line parser, checking required arguments and such.
    // @todo And we have a mem leak here, because parse_arguments reallocs strings.
    Chamber.loggerPushNonFatalOnError();
    success, args, setArgs := CommandLine.parse_arguments(Arguments);
    Chamber.loggerPopNonFatalOnError();
    if !success then return;

    storagePath := Chamber.os_application_data_storage_path(Basic.temp);
    read_json_as(*instance.config, args.config);
    read_json_as(*instance.persistence, Basic.tprint("%.sloubi-chess/persistence.json", storagePath), silentOnError = true);

    instance.engine = Sill.create_engine(SillMeta, .{
        windowTitle = "SloubiChess",
        eventHandler = _event_handler,
        fpsLimit = 60,
        renderEngine = .{
            features = .Window,
            watchShaderFiles = true
        }
    });

    _storage_init();

    if !args.noCache {
        _cache_init(*instance.studies, "studies", instance.STUDIES_VERSION);
        studies_refresh_backlinks();
    }

    _shaders_init();
    _fonts_init();

    instance.sidebar = sidebar_create(); // Keep early, as some entities depend on it.
    instance.controller = controller_create();
    instance.background = background_create();
    instance.library = library_create();
    instance.metaBoard = meta_board_create();
    instance.uci = uci_create();

    send(.SystemReflow);

    if setArgs.pgn {
        study := load_study(args.pgn, .GamesBytes);
        if study != null {
            study_show_game(study, args.gameIndex);
        } else {
            Basic.log("Unable to load PGN %.", args.pgn, flags = .WARNING);
        }
    }

    Sill.engine_run(instance.engine);

    // @todo Probably don't want to cache eveything into a single file, it might be big with a huge database...
    // Reset the .GameBytes computeFlag, as it will not be saved.
    for *study : instance.studies {
        study.computeFlags &= ~.GamesBytes;
        for *game : study.games {
            game.computeFlags &= ~.Plies;
        }
    }
    _cache_commit(*instance.studies, "studies", instance.STUDIES_VERSION);

    // _cleanup();
    // Chamber.cleanup_logger();
    // Basic.report_memory_leaks();
}

#scope_file

_cleanup :: () {
    Basic.reset_temporary_storage();
    Basic.array_free(instance.textMaterialCache);
    config_cleanup(*instance.config);
    persistence_cleanup(*instance.persistence);

    for *study, studyId : instance.studies {
        Basic.free(studyId);
        study_cleanup(study);
    }
    Hash.deinit(*instance.studies);

    Sill.destroy_engine(instance.engine);
}

_event_handler :: (event : Crater.Event) {
    if event.kind == .WindowSizeChanged {
        Magma.forward_renderer_extent(cast(*Magma.ForwardRenderer) instance.engine.renderer, instance.engine.options.windowExtent);
        send(.SystemReflow);
    } else if event.kind == .KeyPressed &&
              event.key.which == Crater.Key.F10 {
        instance.engine.options.logFps = !instance.engine.options.logFps;
    } else if event.kind == .WindowClosed {
        _suggest_close_main_window();
    } else if event.kind == .KeyPressed && event.key.which == .Escape {
        if !controller_handle_escape() && Chamber.BUILD_IS_DEBUG {
            _suggest_close_main_window();
        }
    }
}

_suggest_close_main_window :: () {
    if instance.handlingClosingMainWindow then return;
    instance.handlingClosingMainWindow = true;

    // Check whether there are any unsaved changes.
    foundUnsavedStudies := false;
    for *study : instance.studies {
        if !study.hasUnsavedModifications then continue;
        foundUnsavedStudies = true;
        break;
    }

    if !foundUnsavedStudies {
        instance.engine.closingMainWindow = true;
        return;
    }

    dialogData : DialogData;
    dialogData.mainText = "Do you want to save the changes you made to studies?";
    dialogData.text = "Your changes will be lost if you don't save them.";
    dialogData.choices = .["Save all", "Cancel", "Don't save"];
    dialogData.cancelChoiceIndex = 1;
    dialogData.callback = (dialog : *DialogEntity, choiceIndex : u32, userData : *void) {
        dialog_close(dialog);
        instance.handlingClosingMainWindow = false;

        if choiceIndex == 0 {
            for *study : instance.studies {
                if !study.hasUnsavedModifications then continue;
                study_save(study);
            }
            instance.engine.closingMainWindow = true;
        } else if choiceIndex == 2 {
            instance.engine.closingMainWindow = true;
        }
    };
    dialog_create(dialogData);
}

_fonts_init :: () {
    // @todo We're missing a notion in fonts, which would allow us to use a shared fallback.
    // Currently, we would need to duplicate the "dejaVu" fallback font for each family.
    boldFontFiles : [2]string;
    boldFontFiles[0] = Basic.tprint("./assets/fonts/%-Bold.ttf", instance.config.env.fontFamily);
    boldFontFiles[1] = "./assets/fonts/DejaVuSans.ttf";

    lightFontFiles : [3]string;
    lightFontFiles[0] = Basic.tprint("./assets/fonts/%-Light.ttf", instance.config.env.fontFamily);
    lightFontFiles[1] = "./assets/fonts/DejaVuSans.ttf";
    lightFontFiles[2] = "./assets/fonts/ForkAwesome.ttf";

    lightItalicFontFile := Basic.tprint("./assets/fonts/%-LightItalic.ttf", instance.config.env.fontFamily);

    monoFontFiles : [2]string;
    monoFontFiles[0] = Basic.tprint("./assets/fonts/%-Regular.ttf", instance.config.env.monoFontFamily);
    monoFontFiles[1] = "./assets/fonts/DejaVuSans.ttf";

    Sill.fonts_register(*instance.engine.fonts, "mainLight", lightFontFiles, cast(float) instance.config.env.fontSize);
    Sill.fonts_register(*instance.engine.fonts, "mainLightItalic", lightItalicFontFile, cast(float) instance.config.env.fontSize);
    Sill.fonts_register(*instance.engine.fonts, "mainBold", boldFontFiles, cast(float) instance.config.env.fontSize);
    Sill.fonts_register(*instance.engine.fonts, "mono", monoFontFiles, cast(float) instance.config.env.fontSize);

    // Preload for most common glyphs
    Sill.fonts_glyph_preload(*instance.engine.fonts, "mainLight", "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.,!?-+*/=()[]{}:;<>|&@#$%^~`'\"\\");
    Sill.fonts_glyph_preload(*instance.engine.fonts, "mainBold", "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.,!?-+*/=()[]{}:;<>|&@#$%^~`'\"\\");
}

_shaders_init :: () {
    instance.shaders.gradient = Magma.create_shader(instance.engine.renderer, "./assets/materials/gradient");
    instance.shaders.monochrome = Magma.create_shader(instance.engine.renderer, "./assets/materials/monochrome");
    instance.shaders.text = Magma.create_shader(instance.engine.renderer, "./assets/materials/text", .{ depthWriteEnabled = false, alphaBlendingEnabled = true });
    instance.shaders.translucentMonochrome = Magma.create_shader(instance.engine.renderer, "./assets/materials/translucent-monochrome", .{ depthWriteEnabled = false, alphaBlendingEnabled = true });
    instance.shaders.decorum = Magma.create_shader(instance.engine.renderer, "./assets/materials/decorum", .{ alphaBlendingEnabled = true });
}

_cache_init :: (table : *Hash.Table(string, $T), fileName : string, version : u32) {
    storagePath := Chamber.os_application_data_storage_path(Basic.temp);
    cachePath := Basic.tprint("%.sloubi-chess%cache%0%.bos", storagePath, Chamber.PATH_SEPARATOR, Chamber.PATH_SEPARATOR, fileName);

    Hash.init(table);

    file, success := File.file_open(cachePath, log_errors = false);
    if !success then return;
    defer File.file_close(*file);

    fileData : string;
    fileData, success = File.read_entire_file(file);
    if !success then return;
    defer Basic.free(fileData);

    success = Chamber.bos_deserialize_as(table, fileData, version);
    if success then {
        Basic.log("Loading cache from '%'.", cachePath, flags = .VERBOSE_ONLY);
    } else {
        Basic.log("Loading cache from '%'... failed! (But not to worry, we clear it, then.)", cachePath, flags = .VERBOSE_ONLY);
    }
}

_cache_commit :: (table : *Hash.Table(string, $T), fileName : string, version : u32) {
    storagePath := Chamber.os_application_data_storage_path(Basic.temp);
    cachePath := Basic.tprint("%.sloubi-chess%cache%0%.bos", storagePath, Chamber.PATH_SEPARATOR, Chamber.PATH_SEPARATOR, fileName);
    Basic.log("Saving cache to '%'.", cachePath, flags = .VERBOSE_ONLY);

    file, success := File.file_open(cachePath, for_writing = true, keep_existing_content = false, log_errors = false);
    if !success then return;
    defer File.file_close(*file);

    serializedCache := Chamber.bos_serialize(table.*, version);
    defer Basic.free(serializedCache);
    File.file_write(*file, serializedCache.data, serializedCache.count);
}

_storage_init :: () {
    // All the directories that need to exist to allow saving various files.
    storagePath := Chamber.os_application_data_storage_path(Basic.temp);
    appStoragePath := Basic.tprint("%.sloubi-chess%", storagePath, Chamber.PATH_SEPARATOR);
    cacheStoragePath := Basic.tprint("%cache%", appStoragePath, Chamber.PATH_SEPARATOR);
    libraryStoragePath := Basic.tprint("%library%", appStoragePath, Chamber.PATH_SEPARATOR);
    downloadsStoragePath := Basic.tprint("%downloads", appStoragePath, Chamber.PATH_SEPARATOR);

    File.os_make_directory_if_it_does_not_exist(appStoragePath);
    File.os_make_directory_if_it_does_not_exist(cacheStoragePath);
    File.os_make_directory_if_it_does_not_exist(libraryStoragePath);
    File.os_make_directory_if_it_does_not_exist(downloadsStoragePath);
}

#import "Math";
SimplePackage :: #import "Simple_Package";
