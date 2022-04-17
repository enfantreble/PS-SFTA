
function Get-ProgID {
    <#
    .Synopsis
       Gets all of the ProgIDs registered on a system
    .Description
       Gets all ProgIDs registered on the system. The ProgIDs returned can be used with New-Object -comObject
    .Example
       Get-ProgID
    .Example
        Get-ProgID *Image*
    #>
    param(
        [String]$ProgId = '*'
    )            
    $paths = @('REGISTRY::HKEY_CLASSES_ROOT\CLSID')            
    if ($env:Processor_Architecture -eq 'amd64') {            
        $paths += 'REGISTRY::HKEY_CLASSES_ROOT\Wow6432Node\CLSID'            
    }             
    Get-ChildItem $paths -Include VersionIndependentPROGID -Recurse |
        Where-Object { $_.GetValue('') -like $ProgId } |
        Select-Object @{            
            Name       = 'ProgID'            
            Expression = { $_.GetValue('') }                    
        }, @{
            Name       = 'Library'
            Expression = {
                $inProcServer = Get-ItemProperty "$($_.PSParentPath)\InProcServer32" | Select-Object -ExpandProperty '(default)'                
                if ($inProcServer) { $inProcServer } else {
                    Get-ItemProperty "$($_.PSParentPath)\LocalServer32" | Select-Object -ExpandProperty '(default)'                
                }
            }
        }, @{            
            Name       = '32Bit'            
            Expression = {            
                if ($env:Processor_Architecture -eq 'amd64') {            
                    $_.PSPath.Contains('Wow6432Node')                
                }
                else {            
                    $true            
                }                        
            }            
        }            
} 
function Get-Type {
    <#
    .Synopsis
        Gets the types that are currenty loaded in .NET,
        or gets information about a specific type
    .Description
        Gets all of the loaded types, or gets the possible values for an
        enumerated type or value.
    .Example
        # Gets all loaded types
        Get-Type
    .Example
        # Gets types from System.Management.Automation
        Get-Type -Assembly ([PSObject].Assembly)
    .Example
        # Gets all of the possible values for the ApartmentState property
        [Threading.Thread]::CurrentThread.ApartmentState | Get-Type
    .Example
        # Gets all of the possible values for an apartmentstate
        [Threading.ApartmentState] | Get-Type
    #>
    [CmdletBinding(DefaultParameterSetName = 'Assembly')]   
    param(
        # The assembly to collect types from
        [Parameter(ParameterSetName = 'Assembly', ValueFromPipeline = $true)]
        [Reflection.Assembly[]]
        $Assembly,
    
        # The enumerated value to get all of the possibilties of
        [Parameter(ParameterSetName = 'Enum', ValueFromPipeline = $true)]
        [Enum]
        $Enum,

        # Returns possible values if the Type was an enumerated value
        # Otherwise, returns the static members of the type
        [Parameter(ParameterSetName = 'Type', ValueFromPipeline = $true)]
        [Type[]]
        $Type
    )

    Process {
        switch ($psCmdlet.ParameterSetName) {
            Assembly {
                if (! $psBoundParameters.Count -and ! $args.Count) {
                    $Assembly = [AppDomain]::CurrentDomain.GetAssemblies()
                }
                foreach ($asm in $assembly) {
                    if ($asm) { $asm.GetTypes() }  
                }
            }          
            Type {
                foreach ($t in $type) {
                    if ($t.IsEnum) {
                        [Enum]::GetValues($t)
                    }
                    else {
                        $t | Get-Member -Static
                    }                
                }
            }
            Enum {
                [Enum]::GetValues($enum.GetType())        
            }
        }
    }
}
function Get-ExtensionMethod {
    <#
    .Synopsis
        Gets loaded extension methods
    .Description
        Gets the currently loaded extension methods
    .Example
        Get-ExtensionMethod
    .Link
        Get-Type
    #>
    param()
    [AppDomain]::CurrentDomain.GetAssemblies() |
        ForEach-Object {
            $_.GetTypes()
        } | 
        Where-Object {
            $_.IsPublic -and $_.IsAbstract -and $_.IsSealed -and (-not $_.GetConstructors())
        } |
        ForEach-Object {
            $_.GetMethods('Public, Static')
        } |
        Where-Object {
            $_.GetParameters().Count -ge 1
        }
        
}

function Search-Wmi {
    <#
    .Synopsis
        Searches the WMI repository
    .Description
        Searches the help metadata that is built into the WMI repository
        to find WMI classes to fit a particular need. The search can
        look for:
            - Information by class name
            - Keywords in the description text
            - Keywords in property names or descriptions
            - Keywords in method names or descriptions
    .Example
        # Get all class information from root\cimv2 namespace
        Search-WMI
    .Example
        #
        Search-Wmi -ForName *registry* -Namespace root\default
    .Example
        # Save Everything in Root Default
        Search-Wmi -Namespace root\default | Export-Clixml .\root.default.clixml
    #>
    param(
        # The name of the class you'd like to search for. By default, *
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [String]$ForName = '*',


        # If provided, will search for specific text in a class description
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [String]$ForTextInDescription,
    
        # If provided, will look for specific property names on a wmi class
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]$ForAPropertyLike,
        # If set, will return properties that can write
        [switch]$OnlyIfThePropertyCanWrite,
        # If provided, will look for specific method names on a wmi class
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]$ForAMethodLike,
        # The namespace you'd like to search in, by default root\CIMv2
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]$Namespace = 'root\cimv2',
        # If set, will only return wmi types that can be created
        [switch]$OnlyIfItCanBeCreated,
        # If set, will only return WMI types that can be deleted
        [switch]$OnlyIfItCanBeDeleted,
        # If set, will only return WMI types that can be updated
        [switch]$OnlyIfItCanBeUpdated,        
        # The name of the computer to get WMI information from
        [string]$ComputerName,
        # The credential used to connect to the computer
        [Management.Automation.PSCredential]$Credential,
        # If set, will search recursively
        [Switch]$Recurse,
        # If set, will only search for WMI event classes
        [Switch]$OnlySearchForAnEvent
    )
    
    
    process {
        Get-WmiObject $ForName -Namespace $namespace -Recurse:$Recurse -Amended -List | 
            Select-Object @{
                Name       = 'Class'
                Expression = {
                    Write-Progress 'Getting WMI Data' " $($_.Name)"
                    $_.Name
                    
                }                
            }, @{
                Name       = 'Namespace'
                Expression = {
                    $_.__Namespace 
                }
            }, @{
                Name       = 'Description'
                Expression = {
                        
                    $_.Qualifiers.Item('Description').Value
                }
            }, @{
                Name       = 'CanCreate'
                Expression = {
                    try {
                        [bool](($_.Qualifiers.Item('SupportsCreate').Value))
                    }
                    catch {
                        $false 
                    }                    
                }
            }, @{
                Name       = 'CanUpdate'
                Expression = {
                    try {
                        [bool](($_.Qualifiers.Item('SupportsUpdate').Value))
                    }
                    catch {
                        $false
                    } }                
            }, @{
                Name       = 'CanDelete'
                Expression = {
                    try {
                        [bool]($_.Qualifiers.Item('SupportsDelete').Value)
                    }
                    catch {
                        $false
                    }
                        
                }
            }, @{
                Name       = 'IsAbstract'
                Expression = {
                    try {
                        [bool]($_.Qualifiers.Item('Abstract').Value)
                    }
                    catch {
                        $false
                    }                        
                }
            }, @{
                Name       = 'IsSingleton'
                Expression = {
                    try {
                        [bool]$_.Qualifiers.Item('Singleton').Value                
                    }
                    catch {
                        $false
                    }
                        
                }
            }, @{
                Name       = 'IsAssociation'
                Expression = {
                    try {
                        [bool]$_.Qualifiers.Item('Association').Value                
                    }
                    catch {
                        $false
                    }
                        
                }
            }, @{
                Name       = 'Provider'
                Expression = {
                    try {
                        $_.Qualifiers.Item('Provider').Value                
                    }
                    catch {
                        ''
                    }
                        
                }
            }, @{
                Label      = 'Privileges'
                Expression = { 
                    try {
                        $_.Qualifiers.Item('Privileges').Value -join ','                                        
                    }
                    catch {
                        ''
                    }
                }
            }, @{
                Name       = 'Properties'
                Expression = {
                    $_.Properties | 
                        Select-Object @{
                            Label      = 'PropertyName'
                            Expression = { $_.Name }
                        }, @{
                            Label      = 'PropertyType'
                            Expression = { $_.Type }
                        }, @{
                            Label      = 'Description'
                            Expression = { $_.Qualifiers.Item('Description').Value }
                        }, @{
                            Label      = 'CanRead'
                            Expression = { $_.Qualifiers.Item('Read').Value }
                        }, @{
                            Label      = 'CanWrite'
                            Expression = {
                                try {
                                    $_.Qualifiers.Item('Write').Value
                                }
                                catch {
                                    $false
                                }
                            }
                        }, @{
                            Label      = 'References'
                            Expression = { 
                                try {
                                    $v = $_.Qualifiers.Item('CimType').Value
                                    if ($v -like 'ref:*') {
                                        $v.Substring(4)
                                    }
                                    else {
                                        $null
                                    }
                                }
                                catch {
                                    $false
                                }
                            }
                        }, @{
                            Label      = 'MapsTo'
                            Expression = { 
                                try {
                                    $_.Qualifiers.Item('MappingStrings').Value
                                        
                                }
                                catch {
                                    ''
                                }
                            }
                        }, @{
                            Label      = 'Privileges'
                            Expression = { 
                                try {
                                    $_.Qualifiers.Item('Privileges').Value -join ','                                        
                                }
                                catch {
                                    ''
                                }
                            }
                        }, @{
                            Label      = 'Units'
                            Expression = { 
                                try {
                                    $_.Qualifiers.Item('Units').Value
                                }
                                catch {
                                    ''
                                }
                            }
                        }


                    }
                }, @{
                    Name       = 'Methods'
                    Expression = {
                        $_.Methods | 
                            Select-Object @{
                                Label      = 'MethodName'
                                Expression = { $_.Name }
                            }, @{
                                Label      = 'Description'
                                Expression = { $_.Qualifiers.Item('Description').Value }
                            }, @{
                                Label      = 'MapsTo'
                                Expression = { 
                                    try {
                                        $_.Qualifiers.Item('MappingStrings').Value
                                        
                                    }
                                    catch {
                                        ''
                                    }
                                }
                            }, @{
                                Label      = 'Privileges'
                                Expression = { 
                                    try {
                                        $_.Qualifiers.Item('Privileges').Value -join ','                                        
                                    }
                                    catch {
                                        ''
                                    }
                                }
                            }, @{
                                Label      = 'IsStatic'
                                Expression = {
                                    try {
                                        [bool]$_.Qualifiers.Item('Static').Value
                                    }
                                    catch {
                                        $false 
                                    }
                                }
                            }, @{
                                Label      = 'IsConstructor'
                                Expression = {
                                    try {
                                        [bool]$_.Qualifiers.Item('Constructor').Value
                                    }
                                    catch {
                                        $false 
                                    }
                                }
                            }, @{
                                Label      = 'IsDestructor'
                                Expression = {
                                    try {
                                        [bool]$_.Qualifiers.Item('Destructor').Value
                                    }
                                    catch {
                                        $false 
                                    }
                                }
                            }            
                        }
                    }, @{
                        Name       = 'IsEvent'
                        Expression = { $_.Derivation -contains '__Event' } 
                    }, @{
                        Name       = 'IsSystemClass'
                        Expression = { $_.Derivation -contains '__SystemClass' } 
                    }, @{
                        Name       = 'IsDeprecated'
                        Expression = { 
                            try {
                                $_.Qualifiers.Item('DEPRECATED').Value
                            }
                            catch {
                                $false
                            }
                        } 
                    } |
                    Where-Object {
                        if ($OnlyIfItCanBeCreated) {
                            $stillOk = $_.CanCreate
                            if (-not $stillOk) { return } 
                        }
                        if ($OnlyIfItCanBeDeleted) {
                            $stillOk = $_.CanDelete
                            if (-not $stillOk) { return } 
                        }
                        if ($OnlyIfItCanBeUpdated) {
                            $stillOk = $_.CanUpdate
                            if (-not $stillOk) { return }
                        }
                        if ($ForAPropertyLike) {
                            $stillOk = $_.Properties | 
                                Where-Object { 
                                    ($_.PropertyName -like $ForAPropertyLike -or
                                    $_.Description -like $ForAPropertyLike) -and 
                                    (((-not $OnlyIfThePropertyCanWrite) -or 
                                    ($OnlyIfThePropertyCanWrite -and $_.CanWrite)))
                                }
                                if (-not $stillOk ) { return }
                            }
                    
                            if ($ForAMethodLike) {
                                $stillOk = $_.Methods | 
                                    Where-Object {
                                        $_.MethodName -like $ForAMethodLike -or
                                        $_.Description -like $ForAMethodLike
                                    }
                                    if (-not $stillOk) { return }
                                }
                    
                                if ($OnlySearchForAnEvent) {
                                    $stillOk = $_.IsEvent
                                    if (-not $stillOk) { return }
                                }
                    
                                if ($ForTextInDescription) {
                                    $stillOk = $_.Description -like "*$ForTextInDescription*"
                                    if (-not $stillOk) { return } 
                                }
         
                    
                                    
                                return $true                
                
                            } | ForEach-Object {
                                $_.psobject.typenames.clear()
                                $_.psobject.typenames.add('WmiInfo')
                                $_
                            }
        
        Write-Progress 'Getting WMI Data' 'Complete' -Completed
    }    
}

Get-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.txt\' | Get-ChildItem
Get-ProgID -ProgId .txt