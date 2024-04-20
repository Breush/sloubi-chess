// UCI: Universal Chess Interface
UciEntity :: struct {
    using #as entity : Sill.Entity;

    process : Process.Process;
    thread : Thread.Thread;
    mutex : Thread.Mutex;

    state : UciState;
    responses : [..]UciResponse;
    nextPositionOnBestMove : Position; // Just what's needed for FEN, some array fields might be invalid.

    bestMove : Move;
    bestMoveCentipawns : s64; // Positive is good for white, negative is good for black.
    centipawnsFactor : s64 = 1;

    listener : Sill.ListenerComponent;
    behavior : Sill.BehaviorComponent;
}

UciState :: enum {
    None :: 0;
    InitWaitingForUciOk;
    NewGameWaitingForReadyOk;
    GoStarting;
    GoPollingCentipawns;
    StopWaitingForBestMove;
    Ready;
}

UciCommandKind :: enum {
    None :: 0;
    Uci;
    IsReady;
    UciNewGame;
    Position;
    Stop;
    Go;
}

UciCommand :: struct {
    kind : UciCommandKind;
    args : string;
}

UciResponseKind :: enum u8 {
    None :: 0;
    UciOk;
    ReadyOk;
    IdName;
    IdAuthor;
    Info;
    OptionName; // Well, not how it works...
    BestMove;
}

UciResponse :: struct {
    kind : UciResponseKind;
    value : string; // To be freed, all other strings are views in this.
}

uci_create :: () -> *UciEntity {
    using uci := SillMeta.create_uci_entity(instance.engine);

    uciEnginePath := instance.config.analysis.uciEngine;
    if uciEnginePath.count == 0 then return uci;

    Chamber.loggerPushNonFatalOnError();
    success := Process.create_process(*uci.process, uciEnginePath, capture_and_return_output = true);
    Chamber.loggerPopNonFatalOnError();
    if !success return uci;

    Basic.log("Launched UCI engine: %", uciEnginePath, flags = .VERBOSE_ONLY);

    // Register these only if the process was successfully created.
    Sill.listener_on_message(*listener, _on_message);
    Sill.behavior_on_update(*behavior, _on_update, uci);

    uci.thread.data = uci;
    Thread.init(*uci.mutex);
    Thread.thread_init(*uci.thread, _task);
    Thread.thread_start(*uci.thread);

    uci.state = .InitWaitingForUciOk; Chamber.debug(uci.state);
    _send(uci, .Uci);
    uci.nextPositionOnBestMove.moveIndex = 0xFFFF; // To know that there is nothing to do.

    return uci;
}

uci_set_position :: (uci : *UciEntity, position : Position) {
    if uci.state != .Ready && uci.state != .GoStarting && uci.state != .GoPollingCentipawns && uci.state != .StopWaitingForBestMove then return;

    uci.bestMove = .{};
    send(.UciBestMoveChanged, uci.bestMove);

    if uci.state == .GoStarting {
        uci.nextPositionOnBestMove = position;
        // Note: can't send stop here, because the engine is not ready yet.
        return;
    }

    if uci.state == .StopWaitingForBestMove {
        uci.nextPositionOnBestMove = position;
        return;
    }

    if uci.state == .GoPollingCentipawns {
        uci.nextPositionOnBestMove = position;
        uci.state = .StopWaitingForBestMove; Chamber.debug(uci.state);
        _send(uci, .Stop);
        return;
    }

    _send_position_and_go(uci, position);
}

#scope_file

_on_message :: (using uci : *UciEntity, message : *Message) {
    if message.kind == {
    case .SelectedPlyChanged;
        uci_set_position(uci, message.newPly.position);
    }
}

_on_update :: (dt : float64, uci : *UciEntity) {
    if uci.responses.count == 0 then return;

    newBestMove : Move;
    newBestMoveCentipawns : s64;

    Thread.lock(*uci.mutex);
    for response : uci.responses {
        if uci.state == .InitWaitingForUciOk {
            if response.kind == .UciOk {
                uci.state = .NewGameWaitingForReadyOk; Chamber.debug(uci.state);
                _send(uci, .UciNewGame);
                _send(uci, .IsReady);
            }
        } else if uci.state == .NewGameWaitingForReadyOk {
            if response.kind == .ReadyOk {
                uci.state = .Ready; Chamber.debug(uci.state);
            }
        } else if uci.state == .GoStarting {
            if response.kind == .Info {
                // Whatever, this is depth 1, discard.
                uci.state = .GoPollingCentipawns; Chamber.debug(uci.state);
                if uci.nextPositionOnBestMove.moveIndex != 0xFFFF {
                    uci.state = .StopWaitingForBestMove; Chamber.debug(uci.state);
                    _send(uci, .Stop);
                }
            }
        } else if uci.state == .GoPollingCentipawns {
            if response.kind == .Info {
                found, left, right := String.split_from_right(response.value, " pv ");
                if found {
                    right = String.trim_left(right);
                    newBestMove = algebraic_to_move(right);
                }
                found, left, right = String.split_from_right(response.value, " cp ");
                if found {
                    right = String.trim_left(right);
                    newBestMoveCentipawns = Basic.to_integer(right) * uci.centipawnsFactor;
                }
                found, left, right = String.split_from_right(response.value, " mate ");
                if found {
                    right = String.trim_left(right);
                    mateIn := Basic.to_integer(right);
                    newBestMoveCentipawns = (10000 + Math.abs(mateIn)) * (ifx mateIn < 0 then -1 else 1) * uci.centipawnsFactor;
                }
            }
        } else if uci.state == .StopWaitingForBestMove {
            if response.kind == .BestMove {
                uci.state = .Ready; Chamber.debug(uci.state);
                if uci.nextPositionOnBestMove.moveIndex != 0xFFFF {
                    _send_position_and_go(uci, uci.nextPositionOnBestMove);
                    uci.nextPositionOnBestMove.moveIndex = 0xFFFF;
                    continue;
                }
            }
        } else {
            Basic.assert(false, "Unknown UCI state.");
        }
    }
    uci.responses.count = 0;
    Thread.unlock(*uci.mutex);

    if coord_is_valid(newBestMove.sourceCoord) && coord_is_valid(newBestMove.targetCoord) {
        if uci.bestMove.sourceCoord != newBestMove.sourceCoord ||
            uci.bestMove.targetCoord != newBestMove.targetCoord ||
            uci.bestMove.promotionPieceKind != newBestMove.promotionPieceKind {
            uci.bestMove = newBestMove;
            uci.bestMoveCentipawns = newBestMoveCentipawns;
            send(.UciBestMoveChanged, uci.bestMove);
        }

        if uci.bestMoveCentipawns != newBestMoveCentipawns {
            uci.bestMoveCentipawns = newBestMoveCentipawns;
            send(.UciBestMoveCentipawnsChanged);
        }
    }
}

_task :: (thread : *Thread.Thread) -> s64 {
    uci := cast(*UciEntity) thread.data;

    while true {
        responses : [..]UciResponse;
        responseString : string;

        // All commands ends with a newline. So we read until last character is one.
        while true {
            outBuff : [1024]u8;
            errBuff : [1024]u8;
            Process.read_from_process(*uci.process, outBuff, errBuff, timeout_ms = 300);
            message := Basic.to_string(*outBuff[0], c_style_strlen(*outBuff[0]));
            errMessage := Basic.to_string(*errBuff[0], c_style_strlen(*errBuff[0]));
            if errMessage.count > 0 {
                Basic.log("Error from UCI engine: %", errMessage, flags = .ERROR);
            }
            if message.count == 0 then continue;

            responseString = Basic.tprint("%0%0", responseString, message);
            if responseString[responseString.count - 1] == #char "\n" then break;
        }

        // Convert responseString to an array of responses.
        responseLines := String.split(responseString, cast(u8) #char "\n");
        for responseLine : responseLines {
            if responseLine.count == 0 then continue;
            response : *UciResponse;
            response = Basic.array_add(*responses);
            response.value = responseLine;

            // Chamber.debug("Received: ", response.value);

            if String.begins_with(responseLine, "uciok") {
                response.kind = .UciOk;
                response.value.count = 0;
            } else if String.begins_with(responseLine, "readyok") {
                response.kind = .ReadyOk;
                response.value.count = 0;
            } else if String.begins_with(responseLine, "id name") {
                response.kind = .IdName;
                Basic.advance(*response.value, 8);
            } else if String.begins_with(responseLine, "id author") {
                response.kind = .IdAuthor;
                Basic.advance(*response.value, 10);
            } else if String.begins_with(responseLine, "info") {
                response.kind = .Info;
                Basic.advance(*response.value, 4);
            } else if String.begins_with(responseLine, "option name") {
                response.kind = .OptionName;
                Basic.advance(*response.value, 12);
            } else if String.begins_with(responseLine, "bestmove") {
                response.kind = .BestMove;
                Basic.advance(*response.value, 9);
            } else {
                Basic.log("Unknown UCI response: %\n", responseLine, flags = .WARNING);
            }
            response.value = Basic.sprint("%", String.trim_left(response.value)); // @fixme memleak
        }
        responseString.count = 0;

        Thread.lock(*uci.mutex);
        for response : responses {
            Basic.array_add(*uci.responses, response);
        }
        Thread.unlock(*uci.mutex);
    }

    return 0;
}

_send :: (uci : *UciEntity, command : UciCommandKind, args := "") {
    commandString : string;

    // Send the command.
    if command == .Uci then commandString = "uci";
    else if command == .IsReady then commandString = "isready";
    else if command == .UciNewGame then commandString = "ucinewgame";
    else if command == .Position then commandString = "position";
    else if command == .Stop then commandString = "stop";
    else if command == .Go then commandString = "go infinite"; // movetime 3000"; // @fixme Configurable!

    commandString = Basic.tprint("%0%0%0\n", commandString, ifx args.count > 0 then " " else "", args);
    Process.write_to_process(*uci.process, cast([]u8) commandString);

    Chamber.debug("Sent: ", commandString);
}

_send_position_and_go :: (uci : *UciEntity, position : Position) {
    if position.flags & .Mate then return;

    uci.state = .GoStarting; Chamber.debug(uci.state);
    _send(uci, .Position, Basic.tprint("fen %", position_to_fen(position)));
    _send(uci, .Go);
    uci.centipawnsFactor = ifx position_color_to_play(*position) == .White then 1 else -1;
}

Process :: #import "Process";
Thread :: #import "Thread";