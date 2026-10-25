# PowerShell aliases

# Sorts input objects by size in ascending order.
function SortSize {
    $input | Sort-Object Length
}

# Sorts input objects by size in descending order.
function SortSizeDesc {
    $input | Sort-Object Length -Descending
}

# Returns the top N items from the input.
function Top {
    param ([int]$N = 10)

    $input | Select-Object -First $N
}

# Skips the first N items from the input.
function Skip {
    param ([int]$N = 10)

    $input | Select-Object -Skip $N
}

# Prints each argument passed to the function with its index.
function Write-Argument {
    for($i = 0; $i -lt $args.length; $i++) {
        "$i`: $($args[$i])"
    }
}

