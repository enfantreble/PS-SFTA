
[xml]$inputFile = Get-Content .\file-asociations\appassoc.xml
foreach ($line in $inputFile.DefaultAssociations.Association ) {
    Write-Output $line;
    Write-Output Identifier $line.Identifier;
    Write-Output ProgId $line.ProgId;
    Write-Output ApplicationName $line.ApplicationName;
}