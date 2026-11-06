local addonName, addon = ...;
local L = LibStub("AceLocale-3.0"):NewLocale(addonName, "enUS", true);
if not L then return end
addon.L = LibStub("AceLocale-3.0"):GetLocale(addonName);

-- %s is the coloured "/op" command; keep it in every translation.
L["Click to open the settings"] = "Click to open the settings";
L["Circular class, spec and role icons on every nameplate, live crowd-control icons and instant Healer CC alerts."] = "Circular class, spec and role icons on every nameplate, live crowd-control icons and instant Healer CC alerts.";
L["OPlates only adds icons. Your nameplate addon keeps its own bars and style."] = "OPlates only adds icons. Your nameplate addon keeps its own bars and style.";
L["Type %s or click the minimap button to open the settings."] = "Type %s or click the minimap button to open the settings.";
L["Open settings"] = "Open settings";
L["Test"] = "Test";
L["Hide"] = "Hide";
