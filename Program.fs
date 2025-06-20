(*
========================================================================================
Pomodoro CLI - Interactive Terminal-Based Pomodoro Timer
========================================================================================

Intent:
  This Pomodoro timer implements a typical workflow:
    • Idle --[s]--> Work (a countdown, default 25 minutes)
    • Work (running) --(when countdown reaches 0)--> Break (a countdown, default 5 minutes)
    • Break (running) --(when countdown reaches 0)--> Idle
    • In Work or Break, pressing S suspends the session.
    • In Suspended state, press R to resume.
    • In Work or Break, pressing Esc asks if you want to cancel that session (stop & discard it), returning to Idle.
    • In Idle, pressing Esc asks if you want to quit.
    • H displays help.

Command-line Options:
  --sound-alert             : Enable sound alerts (OFF by default)
  --task-length-min [n]     : Set the work session length to n minutes (default is 25)
  --break-length-min [n]    : Set the break length to n minutes (default is 5)
  --long-break-length-min [n] : Set the long break length to n minutes (default is 20)
  --pomos-before-long-break [n] : Set the number of pomodoros before a long break (default is 4)
  --disable-enlarged-text : Disable large text for state and timer (ON by default)

UI Layout (top to bottom):
  1. Summary line showing accumulated time (mm:ss format) spent in Work, Break, Suspend, and Idle.
  2. "Sessions today:" line showing completed work sessions as 🍅 icons with count vs. estimated total.
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
open System.Runtime.InteropServices
open System.Threading
open Spectre.Console
open Spectre.Console.Rendering
open FSharp.SystemTextJson // Ensure this is present for JsonFSharpConverter
open System.Text.Json.Serialization

// ------------------------------------------------------------
// Default Configuration & Command-Line Option Variables
// ------------------------------------------------------------
let mutable taskLengthMin = 25
let mutable breakLengthMin = 5
let mutable longBreakLengthMin = 20
let mutable pomosBeforeLongBreak = 4
let mutable taskDuration = taskLengthMin * 60 // seconds for a Work session
let mutable breakDuration = breakLengthMin * 60 // seconds for a Break session
let mutable longBreakDuration = longBreakLengthMin * 60 // seconds for a long Break session
let mutable workdayLengthStr = "07:30" // default workday length
let mutable estimatedPomodoros = 0

// ------------------------------------------------------------
// Pomodoro States definition
// ------------------------------------------------------------
type PomodoroState =
    | Work
    | Break
    | Suspend
    | Idle

// ------------------------------------------------------------
// Global Variables
// ------------------------------------------------------------
let mutable currentState = Idle
// Holds the active state when suspended (Work or Break)
let mutable suspendedPrevState = Idle
// Countdown timers for Work and Break sessions (in seconds)
let mutable remainingTaskSeconds = 0
let mutable remainingBreakSeconds = 0
// Session timers for Idle and Suspend (counting UP in seconds)
let mutable idleSessionSeconds = 0
let mutable suspendSessionSeconds = 0
// Count of sessions completed today (only if a Work session fully completes).
let mutable pomodoroCount = 0

// Accumulated total time (in seconds) for summary.
let mutable totalWorkSeconds = 0
let mutable totalBreakSeconds = 0
let mutable totalSuspendSeconds = 0
let mutable totalIdleSeconds = 0

// Sound alert: OFF by default; can be enabled via command-line option.
let mutable soundEnabled = false
let mutable useEnlargedText = true // default ON


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
        for i in 1..5 do
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

/// Format total minutes as "X hours Y minutes".
let formatHoursMinutes totalMinutes =
    if totalMinutes < 0 then
        "0 minutes"
    else
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        match hours, minutes with
        | 0, m -> sprintf "%d minutes" m
        | h, 0 -> sprintf "%d hour%s" h (if h > 1 then "s" else "")
        | h, m -> sprintf "%d hour%s %d minutes" h (if h > 1 then "s" else "") m

/// Parse "hh:mm" string to total minutes.
let parseTime (timeStr: string) =
    try
        let parts = timeStr.Split(':')

        if parts.Length = 2 then
            let hours = int parts.[0]
            let minutes = int parts.[1]
            Some(hours * 60 + minutes)
        else
            None
    with _ ->
        None

let padHeader (header: string) = header.PadRight(10)

let getAppDataPath () =
    let appName = "pomo-tui"
    let home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)

    let path =
        if OperatingSystem.IsWindows() then
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), appName)
        elif OperatingSystem.IsMacOS() then
            Path.Combine(home, "Library", "Application Support", appName)
        else // Linux and other Unix-like systems
            Path.Combine(home, ".local", "share", appName)

    Directory.CreateDirectory(path) |> ignore
    path

// ------------------------------------------------------------
// Pomodoro Calculation
// ------------------------------------------------------------
let calculateEstimatedPomodoros () =
    match parseTime workdayLengthStr with
    | Some plannedMinutes ->
        if plannedMinutes <= 0 then
            estimatedPomodoros <- 0
        else
            let mutable pomos = 0
            let mutable calculatedMins = 0
            // Loop until the calculated time meets or exceeds the planned time
            while calculatedMins < plannedMinutes do
                pomos <- pomos + 1
                let workTime = pomos * taskLengthMin

                // After N pomodoros, there are N breaks.
                // The Nth break is a long one if N is a multiple of pomosBeforeLongBreak.
                let numLongBreaks =
                    if pomosBeforeLongBreak > 0 then
                        pomos / pomosBeforeLongBreak
                    else
                        0

                let numShortBreaks = pomos - numLongBreaks

                let breakTime =
                    (numShortBreaks * breakLengthMin) + (numLongBreaks * longBreakLengthMin)

                calculatedMins <- workTime + breakTime

            estimatedPomodoros <- pomos
    | None -> estimatedPomodoros <- 0

// ------------------------------------------------------------
// Update UI: Display current state, timers, and menu.
// ------------------------------------------------------------
let blockFigletFont =
    try
        FigletFont.Load("block")
    with _ ->
        FigletFont.Default

let smallFigletFont =
    try
        FigletFont.Load("small")
    with _ ->
        FigletFont.Default

let renderPomodoroIcons completedPomodoros totalPomodoros pomosBeforeLongBreak =
    let icons = System.Text.StringBuilder()
    let completedPomoColor = "red"
    let completedBreakColor = "yellow"

    for i in 1..totalPomodoros do
        // Append pomodoro icon (colored if completed, grey if not)
        if i <= completedPomodoros then
            icons.Append(sprintf "[%s]🍅[/]" completedPomoColor) |> ignore
        else
            icons.Append("[dim]🍅[/]") |> ignore

        // Append long break icon after a group, if applicable
        if pomosBeforeLongBreak > 0 && i % pomosBeforeLongBreak = 0 && i < totalPomodoros then
            // Check if all pomodoros in this group are completed
            let allCompleted = completedPomodoros >= i

            if allCompleted then
                icons.Append(sprintf " [%s]⏰[/]" completedBreakColor) |> ignore // Completed group
            else
                icons.Append(" [dim]⏰[/]") |> ignore // Incomplete group

    icons.ToString()

let updateUI () =
    Console.Clear()
    // 1. Sessions Today line.
    let sessionsHeader = padHeader "Sessions:"

    let sessionsIcons =
        renderPomodoroIcons pomodoroCount estimatedPomodoros pomosBeforeLongBreak

    AnsiConsole.MarkupLine(
        sprintf "[bold cyan]%s[/] %s ( %d / %d )" sessionsHeader sessionsIcons pomodoroCount estimatedPomodoros
    )

    // 2. Summary line (show times for each state in mm:ss, each in its own color, but timers in white), aligned.
    let summaryHeader = padHeader "Summary:"
    let workTime = formatTime totalWorkSeconds
    let breakTime = formatTime totalBreakSeconds
    let suspendTime = formatTime totalSuspendSeconds
    let idleTime = formatTime totalIdleSeconds

    AnsiConsole.MarkupLine(
        sprintf
            "[bold cyan]%s[/] [green]Work:[/] [white]%s[/] | [blue]Break:[/] [white]%s[/] | [red]Suspend:[/] [white]%s[/] | [yellow]Idle:[/] [white]%s[/]"
            summaryHeader
            workTime
            breakTime
            suspendTime
            idleTime
    )

    // 3. Current state and its timer, using FigletText if enabled.
    if useEnlargedText then
        match currentState with
        | Work ->
            let workText = FigletText(blockFigletFont, "WORK")
            workText.Color <- Color.Green
            AnsiConsole.Write(workText :> IRenderable)

            let workTimer = FigletText(smallFigletFont, formatTime remainingTaskSeconds)
            workTimer.Color <- Color.White
            AnsiConsole.Write(workTimer :> IRenderable)
        | Break ->
            let breakText = FigletText(blockFigletFont, "BREAK")
            breakText.Color <- Color.Blue
            AnsiConsole.Write(breakText :> IRenderable)

            let breakTimer = FigletText(smallFigletFont, formatTime remainingBreakSeconds)
            breakTimer.Color <- Color.White
            AnsiConsole.Write(breakTimer :> IRenderable)
        | Suspend ->
            let suspText =
                match suspendedPrevState with
                | Work -> "WORK (SUSPENDED)"
                | Break -> "BREAK (SUSPENDED)"
                | _ -> "SUSPENDED"

            let suspendText = FigletText(blockFigletFont, suspText)
            suspendText.Color <- Color.Red
            AnsiConsole.Write(suspendText :> IRenderable)

            let suspendTimer = FigletText(smallFigletFont, formatTime suspendSessionSeconds)
            suspendTimer.Color <- Color.White
            AnsiConsole.Write(suspendTimer :> IRenderable)
        | Idle ->
            let idleText = FigletText(blockFigletFont, "IDLE")
            idleText.Color <- Color.Yellow
            AnsiConsole.Write(idleText :> IRenderable)

            let idleTimer = FigletText(smallFigletFont, formatTime idleSessionSeconds)
            idleTimer.Color <- Color.White
            AnsiConsole.Write(idleTimer :> IRenderable)
    else
        match currentState with
        | Work ->
            let workHeader = padHeader "Work:"
            let workTimer = formatTime remainingTaskSeconds
            AnsiConsole.MarkupLine(sprintf "[green]%s[/] [white]%s[/]" workHeader workTimer)
        | Break ->
            let breakHeader = padHeader "Break:"
            let breakTimer = formatTime remainingBreakSeconds
            AnsiConsole.MarkupLine(sprintf "[blue]%s[/] [white]%s[/]" breakHeader breakTimer)
        | Suspend ->
            match suspendedPrevState with
            | Work ->
                let suspHeader = padHeader "Work (Susp.):"
                let suspTimer = formatTime suspendSessionSeconds
                AnsiConsole.MarkupLine(sprintf "[red]%s[/] [white]%s[/]" suspHeader suspTimer)
            | Break ->
                let suspHeader = padHeader "Break (Susp.):"
                let suspTimer = formatTime suspendSessionSeconds
                AnsiConsole.MarkupLine(sprintf "[red]%s[/] [white]%s[/]" suspHeader suspTimer)
            | _ ->
                let suspHeader = padHeader "Suspended:"
                let suspTimer = formatTime suspendSessionSeconds
                AnsiConsole.MarkupLine(sprintf "[red]%s[/] [white]%s[/]" suspHeader suspTimer)
        | Idle ->
            let idleHeader = padHeader "Idle:"
            let idleTimer = formatTime idleSessionSeconds
            AnsiConsole.MarkupLine(sprintf "[yellow]%s[/] [white]%s[/]" idleHeader idleTimer)

    // 4. Bottom menu line, aligned (no sound icon).
    let menuHeader = padHeader "MENU:"

    let menuLine =
        match currentState with
        | Idle -> sprintf "%s S\u0332tart | Se\u0332ttings | H\u0332elp | Q\u0332uit" menuHeader
        | Work -> sprintf "%s S\u0332uspend | C\u0332ancel | Se\u0332ttings | H\u0332elp" menuHeader
        | Break -> sprintf "%s S\u0332uspend | C\u0332ancel | Se\u0332ttings | H\u0332elp" menuHeader
        | Suspend -> sprintf "%s R\u0332esume | Se\u0332ttings | H\u0332elp" menuHeader

    AnsiConsole.MarkupLine(sprintf "[bold cyan]%s[/]" menuLine)

// ------------------------------------------------------------
// Help Display
// ------------------------------------------------------------
let displayHelp () =
    Console.Clear()
    AnsiConsole.MarkupLine("[bold cyan]Pomodoro CLI - Command Help[/]")
    AnsiConsole.MarkupLine("[bold green]Idle state:[/] Start (s), Help (h), Quit (q)")
    AnsiConsole.MarkupLine("[bold green]Work state:[/] Suspend (s), Cancel (c), Help (h)")
    AnsiConsole.MarkupLine("[bold green]Break state:[/] Suspend (s), Cancel (c), Help (h)")
    AnsiConsole.MarkupLine("[bold green]Suspend state:[/] Resume (r), Help (h)")
    Console.WriteLine("Press any key to return...")
    Console.ReadKey(true) |> ignore

// ------------------------------------------------------------
// Settings Display
// ------------------------------------------------------------
let displaySettings () =
    Console.Clear()
    AnsiConsole.MarkupLine("[bold cyan]Pomodoro CLI - Settings[/]")
    AnsiConsole.MarkupLine("")

    let appDataPath = getAppDataPath ()

    AnsiConsole.MarkupLine(sprintf "💾 [bold]Data folder:[/] [white]%s[/]" appDataPath)

    AnsiConsole.MarkupLine("[grey]Settings can only be changed via command-line options at launch.[/]")

    AnsiConsole.MarkupLine("")

    AnsiConsole.MarkupLine(
        sprintf
            "🖼️  [bold]Enlarged state/timer text:[/] [white]%s[/]  [grey](disable with --disable-enlarged-text)[/]"
            (if useEnlargedText then "ON" else "OFF")
    )

    AnsiConsole.MarkupLine(
        "[grey]When enabled, the current state and timer are shown as large outlined text for better visibility.[/]"
    )

    AnsiConsole.MarkupLine("")

    let alarmIcon = if soundEnabled then "🔔" else "🔕"
    let alarmStatus = if soundEnabled then "ON" else "OFF"

    AnsiConsole.MarkupLine(
        sprintf "%s [bold]Alarm:[/] [white]%s[/]  [grey](toggle with --sound-alert at launch)[/]" alarmIcon alarmStatus
    )

    AnsiConsole.MarkupLine("")

    AnsiConsole.MarkupLine(
        sprintf
            "⏱️  [bold]Work session length:[/] [white]%d[/] min  [grey](set with --task-length-min)[/]"
            taskLengthMin
    )

    AnsiConsole.MarkupLine(
        sprintf
            "☕ [bold]Break session length:[/] [white]%d[/] min  [grey](set with --break-length-min)[/]"
            breakLengthMin
    )

    AnsiConsole.MarkupLine(
        sprintf
            "☕ [bold]Long break session length:[/] [white]%d[/] min  [grey](set with --long-break-length-min)[/]"
            longBreakLengthMin
    )

    AnsiConsole.MarkupLine(
        sprintf
            "🍅 [bold]Pomodoros before long break:[/] [white]%d[/]  [grey](set with --pomos-before-long-break)[/]"
            pomosBeforeLongBreak
    )

    AnsiConsole.MarkupLine("")

    let plannedWorkdayDisplay =
        match parseTime workdayLengthStr with
        | Some mins -> formatHoursMinutes mins
        | None -> workdayLengthStr // Fallback

    AnsiConsole.MarkupLine(
        sprintf
            "🗓️  [bold]Planned workday length:[/] [white]%s[/]  [grey](set with --workday-length [[hh:mm]])[/]"
            plannedWorkdayDisplay
    )

    AnsiConsole.MarkupLine("")

    if estimatedPomodoros > 0 then
        let numLongBreaks =
            if pomosBeforeLongBreak > 0 then
                estimatedPomodoros / pomosBeforeLongBreak
            else
                0

        let numShortBreaks = estimatedPomodoros - numLongBreaks

        let totalCalculatedMinutes =
            (estimatedPomodoros * taskLengthMin)
            + (numShortBreaks * breakLengthMin)
            + (numLongBreaks * longBreakLengthMin)

        let calculatedWorkday = formatHoursMinutes totalCalculatedMinutes

        AnsiConsole.MarkupLine("📊 [bold]Workday estimate:[/]")

        let totalWorkMinutes = estimatedPomodoros * taskLengthMin
        let totalShortBreakMinutes = numShortBreaks * breakLengthMin
        let totalLongBreakMinutes = numLongBreaks * longBreakLengthMin

        AnsiConsole.MarkupLine(
            sprintf
                "            [white]%d pomodoros (%d min):[/] %d min"
                estimatedPomodoros
                taskLengthMin
                totalWorkMinutes
        )

        AnsiConsole.MarkupLine(
            sprintf
                "            [white]%d short breaks (%d min):[/] %d min"
                numShortBreaks
                breakLengthMin
                totalShortBreakMinutes
        )

        AnsiConsole.MarkupLine(
            sprintf
                "              [white]%d long breaks (%d min, each %d pomodoros):[/] %d min"
                numLongBreaks
                longBreakLengthMin
                pomosBeforeLongBreak
                totalLongBreakMinutes
        )

        AnsiConsole.MarkupLine(sprintf "   [bold]Resulting workday length:[/] [white]%s[/]" calculatedWorkday)

    AnsiConsole.MarkupLine("")

    Console.WriteLine("Press any key to return...")
    Console.ReadKey(true) |> ignore

// ------------------------------------------------------------
// State Persistence: Save/Load full state per day
// ------------------------------------------------------------
type PomodoroDayState =
    { PomodoroCount: int
      TotalWorkSeconds: int
      TotalBreakSeconds: int
      TotalSuspendSeconds: int
      TotalIdleSeconds: int
      RemainingTaskSeconds: int
      RemainingBreakSeconds: int
      IdleSessionSeconds: int
      SuspendSessionSeconds: int
      CurrentState: PomodoroState
      SuspendedPrevState: PomodoroState
      LongBreakLengthMin: int
      PomosBeforeLongBreak: int
      WorkdayLengthStr: string }

let getTodayStatePath () =
    let appDataPath = getAppDataPath ()
    let today = DateTime.Now.ToString("yyyy-MM-dd")
    let fileName = sprintf "pomodoro-%s.json" today
    Path.Combine(appDataPath, fileName)

let saveDayState () =
    let state =
        { PomodoroCount = pomodoroCount
          TotalWorkSeconds = totalWorkSeconds
          TotalBreakSeconds = totalBreakSeconds
          TotalSuspendSeconds = totalSuspendSeconds
          TotalIdleSeconds = totalIdleSeconds
          RemainingTaskSeconds = remainingTaskSeconds
          RemainingBreakSeconds = remainingBreakSeconds
          IdleSessionSeconds = idleSessionSeconds
          SuspendSessionSeconds = suspendSessionSeconds
          CurrentState = currentState
          SuspendedPrevState = suspendedPrevState
          LongBreakLengthMin = longBreakLengthMin
          PomosBeforeLongBreak = pomosBeforeLongBreak
          WorkdayLengthStr = workdayLengthStr }

    let options = JsonSerializerOptions()
    options.Converters.Add(JsonFSharpConverter())
    let path = getTodayStatePath ()
    File.WriteAllText(path, JsonSerializer.Serialize(state, options))

let loadDayState () =
    let path = getTodayStatePath ()

    if File.Exists path then
        try
            let options = JsonSerializerOptions()
            options.Converters.Add(JsonFSharpConverter())

            let state =
                JsonSerializer.Deserialize<PomodoroDayState>(File.ReadAllText path, options)

            pomodoroCount <- state.PomodoroCount
            totalWorkSeconds <- state.TotalWorkSeconds
            totalBreakSeconds <- state.TotalBreakSeconds
            totalSuspendSeconds <- state.TotalSuspendSeconds
            totalIdleSeconds <- state.TotalIdleSeconds
            remainingTaskSeconds <- state.RemainingTaskSeconds
            remainingBreakSeconds <- state.RemainingBreakSeconds
            idleSessionSeconds <- state.IdleSessionSeconds
            suspendSessionSeconds <- state.SuspendSessionSeconds
            currentState <- state.CurrentState
            suspendedPrevState <- state.SuspendedPrevState
            longBreakLengthMin <- state.LongBreakLengthMin
            pomosBeforeLongBreak <- state.PomosBeforeLongBreak
            workdayLengthStr <- state.WorkdayLengthStr
        with ex ->
            AnsiConsole.MarkupLine(sprintf "[bold red]Error loading state file:[/] %s" ex.Message)
            Thread.Sleep(2000) // Give user time to see the error
    else
        ()

// Load today's state at startup
loadDayState ()

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
        // Work session fully completed → count session, beep for Break.
        beepBreakSession ()
        pomodoroCount <- pomodoroCount + 1
        currentState <- Break

        if pomodoroCount % pomosBeforeLongBreak = 0 then
            remainingBreakSeconds <- longBreakDuration // start a long Break countdown.
        else
            remainingBreakSeconds <- breakDuration // start a regular Break countdown.
    | Break when remainingBreakSeconds <= 0 ->
        // End of Break → transition to Idle with idle beep.
        beepIdleSession ()
        currentState <- Idle
        idleSessionSeconds <- 0 // reset idle counter.
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
    | Suspend ->
        suspendSessionSeconds <- suspendSessionSeconds + 1
        totalSuspendSeconds <- totalSuspendSeconds + 1
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
            idleSessionSeconds <- 0 // reset idle timer
            // Beep: 2 short beeps for starting a Work session.
            beepTaskSession ()
        | Idle, ConsoleKey.Q -> exit 0
        | Idle, ConsoleKey.H -> displayHelp ()
        | Idle, ConsoleKey.E -> displaySettings ()

        // ---------- Work State ----------
        | Work, ConsoleKey.S ->
            // Suspend the Work session.
            suspendedPrevState <- Work
            currentState <- Suspend
            suspendSessionSeconds <- 0 // Reset suspend timer
        | Work, ConsoleKey.C ->
            currentState <- Idle
            idleSessionSeconds <- 0
            remainingTaskSeconds <- taskDuration
        | Work, ConsoleKey.H -> displayHelp ()
        | Work, ConsoleKey.E -> displaySettings ()

        // ---------- Break State ----------
        | Break, ConsoleKey.S ->
            suspendedPrevState <- Break
            currentState <- Suspend
            suspendSessionSeconds <- 0
        | Break, ConsoleKey.C ->
            currentState <- Idle
            idleSessionSeconds <- 0
            remainingBreakSeconds <- breakDuration
        | Break, ConsoleKey.H -> displayHelp ()
        | Break, ConsoleKey.E -> displaySettings ()

        // ---------- Suspend State ----------
        | Suspend, ConsoleKey.R ->
            // Resume the suspended session.
            currentState <- suspendedPrevState
            suspendSessionSeconds <- 0
        | Suspend, ConsoleKey.H -> displayHelp ()
        | Suspend, ConsoleKey.E -> displaySettings ()
        | _ -> ()

    // Save state after each loop iteration for robustness
    saveDayState ()
    Thread.Sleep(1000)
    startLoop ()

/// Parse command-line arguments:
///   --sound-alert
///   --task-length-min [number]
///   --break-length-min [number]
///   --long-break-length-min [number]
///   --pomos-before-long-break [number]
///   --workday-length [hh:mm]
let parseArgs (args: string[]) =
    let rec aux i =
        if i >= args.Length then
            ()
        else
            match args.[i] with
            | "--sound-alert" ->
                soundEnabled <- true
                aux (i + 1)
            | "--task-length-min" ->
                if i + 1 < args.Length then
                    match System.Int32.TryParse(args.[i + 1]) with
                    | true, value ->
                        taskLengthMin <- value
                        taskDuration <- taskLengthMin * 60
                        aux (i + 2)
                    | false, _ ->
                        AnsiConsole.MarkupLine(
                            sprintf
                                "[bold red]Error:[/] Invalid value for %s: '%s'. Using default."
                                args.[i]
                                args.[i + 1]
                        )

                        aux (i + 2)
                else
                    aux (i + 1)
            | "--break-length-min" ->
                if i + 1 < args.Length then
                    match System.Int32.TryParse(args.[i + 1]) with
                    | true, value ->
                        breakLengthMin <- value
                        breakDuration <- breakLengthMin * 60
                        aux (i + 2)
                    | false, _ ->
                        AnsiConsole.MarkupLine(
                            sprintf
                                "[bold red]Error:[/] Invalid value for %s: '%s'. Using default."
                                args.[i]
                                args.[i + 1]
                        )

                        aux (i + 2)
                else
                    aux (i + 1)
            | "--long-break-length-min" ->
                if i + 1 < args.Length then
                    match System.Int32.TryParse(args.[i + 1]) with
                    | true, value ->
                        longBreakLengthMin <- value
                        longBreakDuration <- longBreakLengthMin * 60
                        aux (i + 2)
                    | false, _ ->
                        AnsiConsole.MarkupLine(
                            sprintf
                                "[bold red]Error:[/] Invalid value for %s: '%s'. Using default."
                                args.[i]
                                args.[i + 1]
                        )

                        aux (i + 2)
                else
                    aux (i + 1)
            | "--pomos-before-long-break" ->
                if i + 1 < args.Length then
                    match System.Int32.TryParse(args.[i + 1]) with
                    | true, value ->
                        pomosBeforeLongBreak <- value
                        aux (i + 2)
                    | false, _ ->
                        AnsiConsole.MarkupLine(
                            sprintf
                                "[bold red]Error:[/] Invalid value for %s: '%s'. Using default."
                                args.[i]
                                args.[i + 1]
                        )

                        aux (i + 2)
                else
                    aux (i + 1)
            | "--disable-enlarged-text" ->
                useEnlargedText <- false
                aux (i + 1)
            | "--workday-length" ->
                if i + 1 < args.Length then
                    match parseTime args.[i + 1] with
                    | Some _ ->
                        workdayLengthStr <- args.[i + 1]
                        aux (i + 2)
                    | None ->
                        AnsiConsole.MarkupLine(
                            sprintf
                                "[bold red]Error:[/] Invalid format for %s: '%s'. Use hh:mm. Using default."
                                args.[i]
                                args.[i + 1]
                        )

                        aux (i + 2)
                else
                    aux (i + 1)
            | _ -> aux (i + 1)

    aux 0

[<EntryPoint>]
let main args =
    parseArgs args
    calculateEstimatedPomodoros ()
    // Load today's state at startup (already called above, but ensure it's here)
    loadDayState ()
    // Register handler to save state on exit
    AppDomain.CurrentDomain.ProcessExit.Add(fun _ -> saveDayState ())
    startLoop ()
    0
