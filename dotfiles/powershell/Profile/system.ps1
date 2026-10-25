# Prints each argument passed to the function with its index.
function Write-Args {
    for($i = 0; $i -lt $args.length; $i++) {
        "$i`: $($args[$i])"
    }
}


# Install a package using winget.
function Invoke-Install {
    param (
        [string]$name,
        [string]$package,
        [string]$location = $null,
        [string]$locationExtra = $null
    )

    # log
    Write-Host "`nInstalling ${name}: ${package}"

    # prepare command with location
    $command = "winget install --id $package --accept-package-agreements --no-upgrade --disable-interactivity"
    if ($location) {
        $command += " --location $location"
        if ($locationExtra) {
            $command += " --custom '$locationExtra$location'"
        }
    }

    # execute command
    Write-Host $command
    Invoke-Expression $command
}
