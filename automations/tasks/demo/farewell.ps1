#Requires -Version 5.1
# Task: farewell
# Displays a farewell message

param(
    [string]$target = "World"
)

# Execute task
Write-Host "Goodbye, $target!"

# Return output object (captured by Wrapper)
return @{
    farewell  = "Goodbye"
    target    = $target
    timestamp = (Get-Date).ToString('o')
}
