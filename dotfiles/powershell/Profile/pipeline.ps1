# PowerShell aliases

# Sorts input objects by size in ascending order.
function SortSize {
    param(
        [Parameter(ValueFromPipeline=$true)]
        $Input
    )

    $Input | Sort-Object Length
}

# Sorts input objects by size in descending order.
function SortSizeDesc {
    param(
        [Parameter(ValueFromPipeline=$true)]
        $Input
    )

    $Input | Sort-Object Length -Descending
}

# Returns the top N items from the input.
function Top {
    param(
        [Parameter(ValueFromPipeline=$true)]
        $Input,

        [Parameter(Position = 1, Mandatory = $false)]
        [int]$N = 10
    )

    $Input | Select-Object -First $N
}


# Skips the first N items from the input.
function Skip {

    param(
        [Parameter(ValueFromPipeline=$true)]
        $Input,

        [Parameter(Position = 1, Mandatory = $false)]
        [int]$N = 10
    )
    $Input | Select-Object -Skip $N
}
