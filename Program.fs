(*
========================================================================================
Pomodoro CLI - Interactive Terminal-Based Pomodoro Timer
========================================================================================

Intent:
  This Pomodoro timer implements a typical workflow:
    • Idle --[s]--> Work (a countdown, default 25 minutes)
    • Work (running) --(when countdown reaches 0)--> Break (a countdown, default 5 minutes)
    • Break (running) --(when countdown reaches 0)--> Idle
    • In Work or Break, pressing P pauses the session.
    • In Pause state, press R to resume.
    • In Work or Break, pressing Esc asks if you want to cancel that session (stop & discard it), returning to Idle.
    • In Idle, pressing Esc asks if you want to quit.
    • H displays help.

Command-line Options:
  --sound-alert         : Enable sound alerts (OFF by default)
  --task-length-min [n] : Set the work session length to n minutes (default is 25)
  --break-length-min [n]: Set the break length to n minutes (default is 5)

UI Layout (top to bottom):
  1. Summary line showing accumulated time (mm:ss format) spent in Work, Break, Pause, and Idle.
  2. "Sessions today:" line showing completed work sessions as 🍅 icons with count.
  3. A single-line current state display that shows the state and its timer.
  4. Bottom menu line that adapts to the current state. In Idle it is:
       "🔕 Commands: s (start session) | h (help) | Esc (quit)"

Beep Alerts (if sound enabled):
  - 2 short beeps when starting a Work session.
  - 1 long beep when auto-starting a Break session.
  - 5 short beeps when auto-transitioning to Idle (at the end of a Break).

Only fully completed Work sessions (that run all the way for the set duration) count toward "Sessions today".

========================================================================================
*)

open System
open System.IO
open System.Text.Json
open System.Threading
open Spectre.Console

// ------------------------------------------------------------
// Default Configuration & Command-Line Option Variables
// ------------------------------------------------------------
let mutable taskLengthMin = 25
let mutable breakLengthMin = 5
let mutable taskDuration = taskLengthMin * 60   // seconds for a Work session
let mutable breakDuration = breakLengthMin * 60   // seconds for a Break session
let trackerPath = "pomodoro-tracker.json"
let todayKey = DateTime.Now.ToString("yyyy-MM-dd")

// ------------------------------------------------------------
// Pomodoro States definition
// ------------------------------------------------------------
type PomodoroState = Work | Break | Pause | Idle

// ------------------------------------------------------------
// Global Variables
// ------------------------------------------------------------
let mutable currentState = Idle
// Holds the active state when pausing (Work or Break)
let mutable pausedPrevState = Idle
// Countdown timers for Work and Break sessions (in seconds)
let mutable remainingTaskSeconds = 0
let mutable remainingBreakSeconds = 0
// Session timers for Idle and Pause (counting UP in seconds)
let mutable idleSessionSeconds = 0
let mutable pauseSessionSeconds = 0
// Count of sessions completed today (only if a Work session fully completes).
let mutable pomodoroCount = 0

// Accumulated total time (in seconds) for summary.
let mutable totalWorkSeconds = 0
let mutable totalBreakSeconds = 0
let mutable totalPauseSeconds = 0
let mutable totalIdleSeconds = 0

// Sound alert: OFF by default; can be enabled via command-line option.
let mutable soundEnabled = false

// ------------------------------------------------------------
// Persistence: Load/Save today's count of sessions.
// ------------------------------------------------------------
let loadPomodoroCount () =
    if File.Exists trackerPath then
        let data = File.ReadAllText trackerPath |> JsonSerializer.Deserialize<Map<string,int>>
        match data.TryFind todayKey with
        | Some count -> count
        | None -> 0
    else 0

let savePomodoroCount count =
    let data =
        if File.Exists trackerPath then File.ReadAllText trackerPath |> JsonSerializer.Deserialize<Map<string,int>>
        else Map.empty
    let updatedData = data.Add(todayKey, count)
    File.WriteAllText(trackerPath, JsonSerializer.Serialize(updatedData))

do pomodoroCount <- loadPomodoroCount ()

// ------------------------------------------------------------
// Beep Functions (simulate beep feedback via text output)
// ------------------------------------------------------------
let beepTaskSession () =
    if soundEnabled then
        // 2 short beeps
        AnsiConsole.Markup("[bold yellow]beep[/] ")
        Thread.Sleep(100)
        AnsiConsole.MarkupLine("[bold yellow]beep[/]")

let beepBreakSession () =
    if soundEnabled then
        // 1 long beep
        AnsiConsole.MarkupLine("[bold yellow]BEEP![/]")

let beepIdleSession () =
    if soundEnabled then
        // 5 short beeps
        for i in 1 .. 5 do
            AnsiConsole.Markup("[bold yellow]beep[/] ")
            Thread.Sleep(50)
        AnsiConsole.MarkupLine("")

// ------------------------------------------------------------
// Utility Functions
// ------------------------------------------------------------
/// Format seconds as an MM:SS string.
let formatTime seconds =
    let minutes = seconds / 60
    let secs = seconds % 60
    sprintf "%02d:%02d" minutes secs

// ------------------------------------------------------------
// UI Update: Render summary, sessions today, current state, and bottom menu.
// ------------------------------------------------------------
let updateUI () =
    Console.Clear()
    // 1. Summary line (show times for each state in mm:ss).
    AnsiConsole.MarkupLine(
      sprintf "[bold cyan]Summary:[/] Work: %s | Break: %s | Pause: %s | Idle: %s"
              (formatTime totalWorkSeconds)
              (formatTime totalBreakSeconds)
              (formatTime totalPauseSeconds)
              (formatTime totalIdleSeconds)
    )
    // 2. Sessions Today line.
    let sessionsToday = String.replicate pomodoroCount "🍅"
    AnsiConsole.MarkupLine(sprintf "[bold green]Sessions today:[/] %s ( %d )" sessionsToday pomodoroCount)

    // 3. Current state and its timer on one line.
    let (stateColor, stateText, timerDisplay) =
        match currentState with
        | Work -> ("green", "Work", formatTime remainingTaskSeconds)
        | Break -> ("red", "Break", formatTime remainingBreakSeconds)
        | Pause ->
            ("magenta",
             (match pausedPrevState with
              | Work -> "Work (Paused)"
              | Break -> "Break (Paused)"
              | _ -> "Paused"),
             formatTime pauseSessionSeconds)
        | Idle -> ("yellow", "Idle", formatTime idleSessionSeconds)
    AnsiConsole.MarkupLine(sprintf "[%s]%s[/] : %s" stateColor stateText timerDisplay)

    // 4. Bottom menu line with sound icon.
    let soundIcon = if soundEnabled then "🔔" else "🔕"
    let menuLine =
        match currentState with
        | Idle  -> sprintf "%s Commands: s (start session) | h (help) | Esc (quit)" soundIcon
        | Work  -> sprintf "%s Commands: p (pause) | Esc (cancel) | h (help)" soundIcon
        | Break -> sprintf "%s Commands: p (pause) | Esc (cancel) | h (help)" soundIcon
        | Pause -> sprintf "%s Commands: r (resume) | h (help)" soundIcon
    AnsiConsole.MarkupLine(sprintf "[bold cyan]%s[/]" menuLine)

// ------------------------------------------------------------
// Help Display
// ------------------------------------------------------------
let displayHelp () =
    Console.Clear()
    AnsiConsole.MarkupLine("[bold cyan]Pomodoro CLI - Command Help[/]")
    AnsiConsole.MarkupLine("[bold green]Idle state:[/] s (start session), h (help), Esc (quit)")
    AnsiConsole.MarkupLine("[bold green]Work state:[/] p (pause), Esc (cancel session), h (help)")
    AnsiConsole.MarkupLine("[bold green]Break state:[/] p (pause), Esc (cancel session), h (help)")
    AnsiConsole.MarkupLine("[bold green]Pause state:[/] r (resume), h (help)")
    Console.WriteLine("Press any key to return...")
    Console.ReadKey(true) |> ignore

// ------------------------------------------------------------
// Automatic State Transitions
//   • When Work countdown reaches 0, auto-transition to Break (and count the session).
//   • When Break countdown reaches 0, auto-transition to Idle.
//   • Beep feedback is issued at transitions.
// ------------------------------------------------------------
let autoTransition () =
    match currentState with
    | Work when remainingTaskSeconds <= 0 ->
         // Work session fully completed → count session, beep for Break.
         beepBreakSession ()
         currentState <- Break
         remainingBreakSeconds <- breakDuration  // start Break countdown.
         pomodoroCount <- pomodoroCount + 1
    | Break when remainingBreakSeconds <= 0 ->
         // End of Break → transition to Idle with idle beep.
         beepIdleSession ()
         currentState <- Idle
         idleSessionSeconds <- 0  // reset idle counter.
    | _ -> ()

// ------------------------------------------------------------
// Main Loop: Update timers, process key input, and perform auto-transitions.
// ------------------------------------------------------------
let rec startLoop () =
    autoTransition ()

    // Update timers & accumulate total time.
    match currentState with
    | Work ->
         remainingTaskSeconds <- remainingTaskSeconds - 1
         totalWorkSeconds <- totalWorkSeconds + 1
    | Break ->
         remainingBreakSeconds <- remainingBreakSeconds - 1
         totalBreakSeconds <- totalBreakSeconds + 1
    | Pause ->
         pauseSessionSeconds <- pauseSessionSeconds + 1
         totalPauseSeconds <- totalPauseSeconds + 1
    | Idle ->
         idleSessionSeconds <- idleSessionSeconds + 1
         totalIdleSeconds <- totalIdleSeconds + 1

    updateUI ()

    // Process key input if available.
    if Console.KeyAvailable then
        let keyInfo = Console.ReadKey(true)
        match currentState, keyInfo.Key with
        // ---------- Idle State ----------
        | Idle, ConsoleKey.S ->
            // Start a Work session from Idle.
            currentState <- Work
            remainingTaskSeconds <- taskDuration
            idleSessionSeconds <- 0  // reset idle timer
            // Beep: 2 short beeps for starting a Work session.
            beepTaskSession ()
        | Idle, ConsoleKey.Escape ->
            Console.Write("Quit? (y/n): ")
            if Console.ReadLine() = "y" then exit 0
        | Idle, ConsoleKey.H ->
            displayHelp ()

        // ---------- Work State ----------
        | Work, ConsoleKey.P ->
            // Pause the Work session.
            pausedPrevState <- Work
            currentState <- Pause
            pauseSessionSeconds <- 0  // reset pause timer
        | Work, ConsoleKey.Escape ->
            Console.Write("Cancel current Work session? (y/n): ")
            if Console.ReadLine() = "y" then
                currentState <- Idle
                idleSessionSeconds <- 0
                remainingTaskSeconds <- taskDuration
        | Work, ConsoleKey.H ->
            displayHelp ()

        // ---------- Break State ----------
        | Break, ConsoleKey.P ->
            pausedPrevState <- Break
            currentState <- Pause
            pauseSessionSeconds <- 0
        | Break, ConsoleKey.Escape ->
            Console.Write("Cancel current Break session? (y/n): ")
            if Console.ReadLine() = "y" then
                currentState <- Idle
                idleSessionSeconds <- 0
                remainingBreakSeconds <- breakDuration
        | Break, ConsoleKey.H ->
            displayHelp ()

        // ---------- Pause State ----------
        | Pause, ConsoleKey.R ->
            // Resume the paused session.
            currentState <- pausedPrevState
            pauseSessionSeconds <- 0
        | Pause, ConsoleKey.H ->
            displayHelp ()
        | _ -> ()

    Thread.Sleep(1000)
    startLoop ()

/// Parse command-line arguments:
///   --sound-alert
///   --task-length-min [number]
///   --break-length-min [number]
let parseArgs (args: string[]) =
    let rec aux i =
         if i >= args.Length then ()
         else
              match args.[i] with
              | "--sound-alert" ->
                    soundEnabled <- true
                    aux (i+1)
              | "--task-length-min" ->
                    if i+1 < args.Length then
                        let value = int args.[i+1]
                        taskLengthMin <- value
                        taskDuration <- taskLengthMin * 60
                        aux (i+2)
                    else aux (i+1)
              | "--break-length-min" ->
                    if i+1 < args.Length then
                        let value = int args.[i+1]
                        breakLengthMin <- value
                        breakDuration <- breakLengthMin * 60
                        aux (i+2)
                    else aux (i+1)
              | _ -> aux (i+1)
    aux 0

[<EntryPoint>]
let main args =
    parseArgs args
    startLoop ()
    0
