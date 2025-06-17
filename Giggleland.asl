state("Giggleland Demo") { }

startup
{
    //Timing offset and flag
    vars.startTimeOffsetFlag = false;
    vars.startTimeOffset = -0.260;

    vars.SplitCooldownTimer = new Stopwatch();
    vars.PreventStartSplitTimer = new Stopwatch();

    //Load asl-help binary and instantiate it - will inject code into the asl in the background
    Assembly.Load(File.ReadAllBytes("Components/asl-help")).CreateInstance("Unity");

    //Set the helper to load the scene manager, you probably want this (the helper is set at vars.Helper automagically)
    vars.Helper.LoadSceneManager = true;

    //Setting Game Name and toggling alert to ensure runner is comparing against Game TIme
    vars.Helper.GameName = "Giggleland Demo";
    vars.Helper.AlertLoadless();

    //initializing this var to set up load removal with just scenes later
    vars.SceneLoading = "";

    vars.Watch = (Action<IDictionary<string, object>, IDictionary<string, object>, string>)((oldLookup, currentLookup, key) =>
{
    //here we see a wild typescript dev attempting C#... oh, the humanity...
    var currentValue = currentLookup.ContainsKey(key) ? (currentLookup[key] ?? "(null)") : null;
    var oldValue = oldLookup.ContainsKey(key) ? (oldLookup[key] ?? "(null)") : null;

    //print if there's a change
    if (oldValue != null && currentValue != null && !oldValue.Equals(currentValue)) {vars.Log(key + ": " + oldValue + " -> " + currentValue);}
    //first iteration, print starting values
    if (oldValue == null && currentValue != null) {vars.Log(key + ": " + currentValue);}
});

#region TextComponent
    //Dictionary to cache created/reused layout components by their left-hand label (Text1)
    vars.lcCache = new Dictionary<string, LiveSplit.UI.Components.ILayoutComponent>();

    //Function to set (or update) a text component
    vars.SetText = (Action<string, object>)((text1, text2) =>
{
    const string FileName = "LiveSplit.Text.dll";
    LiveSplit.UI.Components.ILayoutComponent lc;

    //Try to find an existing layout component with matching Text1 (label)
    if (!vars.lcCache.TryGetValue(text1, out lc))
    {
        lc = timer.Layout.LayoutComponents.Reverse().Cast<dynamic>()
            .FirstOrDefault(llc => llc.Path.EndsWith(FileName) && llc.Component.Settings.Text1 == text1)
            ?? LiveSplit.UI.Components.ComponentManager.LoadLayoutComponent(FileName, timer);

        //Cache it for later reference
        vars.lcCache.Add(text1, lc);
    }

    //If it hasn't been added to the layout yet, add it
    if (!timer.Layout.LayoutComponents.Contains(lc))
        timer.Layout.LayoutComponents.Add(lc);

    //Set the label (Text1) and value (Text2) of the text component
    dynamic tc = lc.Component;
    tc.Settings.Text1 = text1;
    tc.Settings.Text2 = text2.ToString();
});

    //Function to remove a single text component by its label
    vars.RemoveText = (Action<string>)(text1 =>
{
    LiveSplit.UI.Components.ILayoutComponent lc;

    //If it's cached, remove it from the layout and the cache
    if (vars.lcCache.TryGetValue(text1, out lc))
    {
        timer.Layout.LayoutComponents.Remove(lc);
        vars.lcCache.Remove(text1);
    }
});

    //Function to remove all text components that were added via this script
    vars.RemoveAllTexts = (Action)(() =>
{
    //Remove each one from the layout
    foreach (var lc in vars.lcCache.Values)
        timer.Layout.LayoutComponents.Remove(lc);

    //Clear the cache
    vars.lcCache.Clear();
});
#endregion

    //Settings group for enabling text display options
    settings.Add("textDisplay", true, "Text Options");
    //Controls whether to automatically clean up text components on script exit
    settings.Add("removeTexts", true, "Remove all texts on exit", "textDisplay");

    //Parent 1
    settings.Add("Autosplit Options", true, "Autosplit Options");
    //Child 1 to Parent 1
    //settings.Add("ChapterSplit", true, "Split on Region change", "Autosplit Options");
    settings.Add("SubchapterSplit", true, "Split on Subchapter Change (Somewhat Often)", "Autosplit Options");
    settings.Add("ObjectiveSplit", true, "Split on Objective change (Extremely Often)", "Autosplit Options");

    //Settings group for game related info
    settings.Add("gameInfo", true, "Various Game Info");
    //Sub-settings: this controls whether to show "some value" as a text component
    settings.Add("Chapter: ", true, "Current Chapter", "gameInfo");
    settings.Add("Sub-Chapter: ", true, "Current Sub-Chapter", "gameInfo");
    settings.Add("Objective: ", true, "Current Pinned Objective", "gameInfo");
    settings.Add("Speed: ", false, "Player Speed - Janky AF", "gameInfo");

    //Settings group for Unity related info
    settings.Add("UnityInfo", false, "Unity Scene Info");
    //Sub-settings: this controls whether to show "some value" as a text component
    //One downside to this new method is the setting key ie "Scene Loading?" must be the same as text1 (the left text) - a bit weird but not the end of the world.
    settings.Add("Scene Loading?", false, "Check if a Unity scene is loading", "UnityInfo");
    settings.Add("LScene Name: ", false, "Name of Loading Scene", "UnityInfo");
    settings.Add("AScene Name: ", false, "Name of Active Scene", "UnityInfo");
}

init
{
    //helps clear some errors when scene is null
    current.Scene = "";
    current.activeScene = "";
    current.loadingScene = "";

    //starting the stopwatch for the splitter cooldown
    vars.SplitCooldownTimer.Start();
    vars.PreventStartSplitTimer.Start();


    //Helper function that sets or removes text depending on whether the setting is enabled - only works in `init` or later because `startup` cannot read setting values
    vars.SetTextIfEnabled = (Action<string, object>)((text1, text2) =>
{
    if (settings[text1])            //If the matching setting is checked
        vars.SetText(text1, text2); //Show the text
    else
        vars.RemoveText(text1);     //Otherwise, remove it
});

    //This is where we will load custom properties from the code, EMPTY FOR NOW
    vars.Helper.TryLoad = (Func<dynamic, bool>)(mono =>
    {
    var OM = mono["ObjectiveManager"];
    var FPSC = mono["FirstPersonController"];
    var TMPro = mono["Unity.TextMeshPro", "TMPro.TextMeshProUGUI"];
    vars.Helper["chapterTitle"] = OM.MakeString("Instance", "currentChapterTitle");
    vars.Helper["chapterSubtitle"] = OM.MakeString("Instance", "currentChapterSubtitle");
    vars.Helper["objective"] = OM.MakeString("Instance", "currentObjective");
    vars.Helper["Speed"] = FPSC.Make<float>("Instance", "_moveVelocity");
    return true;
    });

    //Enable if having scene print issues - a custom function defined in init, the `scene` is the scene's address (e.g. vars.Helper.Scenes.Active.Address)
    vars.ReadSceneName = (Func<IntPtr, string>)(scene => {
    string name = vars.Helper.ReadString(256, ReadStringType.UTF8, scene + 0x38);
    return name == "" ? null : name;
    });
}

update
{
    vars.Watch(old, current, "objective");
    vars.Watch(old, current, "Speed");

    if (current.loadingScene == "MainMenu" && current.activeScene == "DemoEnding") 
	{
		print("End Split Offset Executed Successfully");
		const double Offset = 39.367;
		timer.LoadingTimes += TimeSpan.FromSeconds(Offset);
	}

    //error handling
    if(current.chapterTitle == null){current.chapterTitle = "null";}
    if(current.chapterSubtitle == null){current.chapterSubtitle = "null";}
    if(current.objective == null){current.objective = "null";}

    //More text component stuff - checking for setting and then generating the text. No need for .ToString since we do that previously
    vars.SetTextIfEnabled("Scene Loading?",vars.SceneLoading);
    vars.SetTextIfEnabled("LScene Name: ",current.loadingScene);
    vars.SetTextIfEnabled("AScene Name: ",current.activeScene);
    vars.SetTextIfEnabled("Chapter: ",current.chapterTitle);
    vars.SetTextIfEnabled("Sub-Chapter: ",current.chapterSubtitle);
    vars.SetTextIfEnabled("Objective: ",current.objective);

    //Get the current active scene's name and set it to `current.activeScene` - sometimes, it is null, so fallback to old value
    current.activeScene = vars.Helper.Scenes.Active.Name ?? current.activeScene;
    //Usually the scene that's loading, a bit jank in this version of asl-help
    current.loadingScene = vars.Helper.Scenes.Loaded[0].Name ?? current.loadingScene;

    //Log changes to the active scene
    if (old.activeScene != current.activeScene)   {vars.Log("activeScene: " + old.activeScene + " -> " + current.activeScene);}
    if (old.loadingScene != current.loadingScene) {vars.Log("loadingScene: " + old.loadingScene + " -> " + current.loadingScene);}

    //Setting up for load removal & text display of load removal stuff
    if(old.loadingScene != current.loadingScene)  {vars.SceneLoading = "Loading";}
    if(old.activeScene != current.activeScene)    {vars.SceneLoading = "Not Loading";}

    //DEBUG
    //print(current.objective);
}

start
{
    if (old.loadingScene != "VegetablePatch" && current.loadingScene == "VegetablePatch")
    {
        vars.SplitCooldownTimer.Restart();
        vars.PreventStartSplitTimer.Restart();
        vars.startTimeOffsetFlag = true;
        timer.IsGameTimePaused = true;
        return true;
    }
}

onStart
{
    vars.Log("activeScene: " + current.activeScene);
    vars.Log("loadingScene: " + current.loadingScene);
}

split
{
    if(vars.SplitCooldownTimer.Elapsed.TotalSeconds < 5 || vars.PreventStartSplitTimer.Elapsed.TotalSeconds < 10) {return false;}

    if
    (
        settings["SubchapterSplit"] && current.chapterSubtitle != old.chapterSubtitle && old.chapterSubtitle != "null" ||
        settings["ObjectiveSplit"] && current.objective != old.objective && old.objective != "null"
    )
    {
        vars.SplitCooldownTimer.Restart();
        return true;
    }
}

isLoading
{
    return vars.SceneLoading == "Loading";
}

gameTime
{
    if(vars.startTimeOffsetFlag) 
    {
        vars.startTimeOffsetFlag = false;
        return TimeSpan.FromSeconds(vars.startTimeOffset);
    }
}

exit
{
    //Clean up all text components when the script exits
    if (settings["removeTexts"])
    vars.RemoveAllTexts();
}
