-- Minimal Aseprite filesystem mock for tests running on any host OS.
return {
  filePath = function(path)
    return path:gsub("\\", "/"):match("^(.*)/") or "."
  end,
  joinPath = function(a, b)
    return a .. "/" .. b
  end,
}
