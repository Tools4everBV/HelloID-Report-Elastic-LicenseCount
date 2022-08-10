<#
    TOOLS4EVER GET LICENSE COUNTS V1.0.0
.SYNOPSIS
.DESCRIPTION
.NOTES
    Author: Ronald Kamerbeek
    Editor: Ramon Schouten
    Last Edit: 2022-08-10
    Version 1.0.0 - initial release
#>

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region define parameters
# Amount of items to query
$Count = 500

# Range From (Greater than or equal) 
$rangeGte = "now+1m-1M/M"  # Elastic date math value. For more info, please see Elastic docs: https://www.elastic.co/guide/en/elasticsearch/reference/7.17/query-dsl-range-query.html#ranges-on-dates

# Range To (Less than)
$rangeLt = "now/M" # Elastic date math value. For more info, please see Elastic docs: https://www.elastic.co/guide/en/elasticsearch/reference/7.17/query-dsl-range-query.html#ranges-on-dates

# API username + password connect to Elastic (one entry in the array for each tenant).
$elasticTenantApiData = @(
    [pscustomobject]@{
        ApiUsername = "<Elastic API Username of HelloID tenant 1>"
        ApiSecret   = "<Elastic API Secret of HelloID tenant 1>"
    }
    ,[pscustomobject]@{
        ApiUsername = "<Elastic API Username of HelloID tenant 2>"
        ApiSecret   = "<Elastic API Secret of HelloID tenant 2>"
    } 
    <#, 3,4,5, etc  #>
)
#endregion define parameters used to connect to Elastic (one entry in the array for each tenant).

#region functions
# Create authorization headers with HelloID Tenant Elastic API key
function New-AuthorizationHeaders {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Username,

        [Parameter()]
        [string]
        $Password
    )
    try {
        $pair = "$($Username):$($Password)"
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
        $base64 = [System.Convert]::ToBase64String($bytes)
        $key = "Basic $base64"
        $headers = @{ Authorization = $Key }

        return $headers
    }
    catch {
        $ex = $PSItem
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error message: $($ex)"
        throw "Could not create authorization headers. Error: $($ex.Exception.Message)"
    }
}

####Get the data
# Body can be changed according to needs defaults to 500 results of the last month
function Get-ElasticLicenseCount {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Username,

        [Parameter()]
        [string]
        $Password,

        [Parameter(Mandatory)]
        [int]
        $Count = 500,

        [Parameter(Mandatory)]
        [string]
        $RangeGte = "now+1m-1M/M",

        [Parameter(Mandatory)]
        [string]
        $RangeLt = "now/M"
    )
    # Create authorization headers with HelloID Tenant Elastic API key
    try {
        $pair = "$($Username):$($Password)"
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
        $base64 = [System.Convert]::ToBase64String($bytes)
        $key = "Basic $base64"
        $headers = @{ Authorization = $Key }
    }
    catch {
        $ex = $PSItem
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error message: $($ex)"
        throw "Could not create authorization headers. Error: $($ex.Exception.Message)"
    }

    # Query Elastic data
    try {
        $body = "{
            ""size"": $Count,
            ""sort"": [
                {
                    ""logDate"": {
                        ""order"": ""desc"",
                        ""unmapped_type"": ""boolean""
                    }
                }
            ],
            ""query"": {
                ""bool"": {
                    ""must"": [],
                    ""filter"": [
                        {
                            ""bool"": {
                                ""should"": [
                                    {
                                        ""match_phrase"": {
                                            ""_index"": ""general-license-counts""
                                        }
                                    }
                                ],
                                ""minimum_should_match"": 1
                            }
                        },
                        {
                            ""range"": {
                                ""logDate"": {
                                    ""format"": ""strict_date_optional_time"",
                                    ""gte"": ""$RangeGte"",
                                    ""lt"": ""$RangeLt""
                                }
                            }
                        },
                        {
                            ""match_phrase"": {
                                ""_index"": ""general-license-counts""
                            }
                        }
                    ]
                }
            }
        }"

        $splatParams = @{
            Method      = 'Post'
            Uri         = 'https://we-identity.helloid.cloud/service/elastic-proxy/elastic/_search'
            Headers     = $Headers
            Body        = $body
            ContentType = 'application/json'
        }

        $response = Invoke-RestMethod @splatParams

        return $response.hits.hits._source 
    }
    catch {
        $ex = $PSItem
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error message: $($ex)"
        throw "Could not query Elastic data. Error: $($ex.Exception.Message)"
    }
}
#endregion functions

# Retreive the results
$results = @()
$elasticTenantApiData | ForEach-Object {
    # Query Elastic License count
    try {
        $splatParams = @{
            Username = $_.ApiUsername
            Password = $_.ApiSecret
            Count    = $count
            RangeGte = $rangeGte
            RangeLt = $rangeLt
        }

        $licenseCount = Get-ElasticLicenseCount @splatParams
        $results += $licenseCount
    }
    catch {
        $ex = $PSItem
        throw "Could not query license count from Elastic. Error: $($ex.Exception.Message)"
    }
}

# Example to export results to a CSV file
$results | Export-Csv "C:\Temp\HelloID Elastic License Count.csv" -Delimiter ';' -Encoding UTF8 -NoTypeInformation 