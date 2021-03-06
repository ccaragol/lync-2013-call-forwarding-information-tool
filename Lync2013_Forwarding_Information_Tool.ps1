<# 
.Synopsis 
   The purpose of this tool is to give you an easy front end GUI to review your user's call forwarding
   settings.  This information can be difficult to retreive without a utility such as sefautil, so I've
   extracted it from export-csuserdata for display.  This tool writes no data back to Lync.  Skype for 
   Business includes additional fields which would remain empty in a Lync 2013 environment, which is why
   there are seperate tools for each.
 
.DESCRIPTION 
   PowerShell GUI script which allows for flexibility in the review of Lync user Call Forwarding Information
 
.Notes 
     NAME:      lync2013_forwarding_information_tool.ps1
     VERSION:   1.0 
     AUTHOR:    C. Anthony Caragol 
     LASTEDIT:  05/14/2015
      
   V 1.0 - May 14 2015 - Initial release 
    
.Link 
   Website: http://www.skypeadmin.com
   Twitter: http://www.twitter.com/canthonycaragol
   LinkedIn: http://www.linkedin.com/in/canthonycaragol
 
.EXAMPLE 
   .\Lync2013_Forwarding_Information_tool.ps1

.TODO
  1) I should probably add some more comments, see .APOLOGY

.APOLOGY
  Please excuse the sloppy coding, I don't use a development environment, IDE or ISE.  I use notepad, 
  not even Notepad++, just notepad.  I am not a developer, just an enthusiast so some code may be redundant or
  inefficient.  If you spot a way to make it better, please reach out at via the Q/A in the TechNet gallery or 
  find me at a link above.
#>

[void] [Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem")
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

Function LoadDataIntoArray()
{
	$global:ForwardingInfoArray.Clear()
	$TempFolder = (Get-Item -Path ".\" -Verbose).FullName
	$TempFolder = $TempFolder + "\Lync_Forwarding_Review_Tool_Temp"
	$CurrentContentFolder = $TempFolder + "\Current_Content"
	$CurrentContentFilename = $CurrentContentFolder + "\ExportedUserData.zip"

	If(Test-Path $CurrentContentFolder)
	{
		Remove-Item "$CurrentContentFolder" -ErrorAction:Stop -Recurse
	}

	If(!(Test-Path $CurrentContentFolder))
	{
		New-Item -ItemType Directory -Path $CurrentContentFolder
	}

	Export-CsUserData -PoolFqdn $PoolDropDownComboBox.SelectedItem.tostring()  -FileName $CurrentContentFilename

	[System.IO.Compression.ZipFile]::ExtractToDirectory($CurrentContentFilename, $CurrentContentFolder)
	[xml]$LyncXMLFile = Get-Content "$CurrentContentFolder\DocItemSet.xml"

	$XMLHighLevel = $LyncXMLFile.DocItemSet.DocItem| ?{$_.Name -like "urn:lcd:*"}
	Foreach ($XMLHolder in $XMLHighLevel) 
	{ 
		#Get the User's SIP Address
		$SipName=$XMLHolder.Name.substring(8, $XMLHolder.Name.length - 8)
	
		#Get the user's pure delegate list 
		$DelegatesTag=@($XMLHolder.Data.HomedResource.Delegates)
		$AllDelegates = @()
		if ($DelegatesTag.OuterXML.length -gt 0)
		{
			foreach ($delegate in $DelegatesTag.Delegate) { $AllDelegates += $delegate.uri }
		}

	$node = @($XMLHolder.Data.HomedResource.Containers.Container) | where {$_.ContainerNumber -eq '0'}
	$ExistingContainers = $node.Publication
	$UsedGroupArray = @()
	foreach ($x in  $ExistingContainers) 
	{ 
		if ($x.CategoryName -eq "routing" -and $x.InstanceNum -eq "0")
		{
			$DisplayName = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($x.Data))
			$DNEncoded=[System.Convert]::ToBase64String([System.Text.Encoding]::UNICODE.GetBytes($DisplayName))

			#Is this redundant?  Yeah.
			[xml]$RoutingXML = $DisplayName

			#Set our no answer to placeholder value to voicemail, if no entry is specified, the client will check for voicemail.
			$NoVarAnswerTo="Attempt Voice Mail"

			$clientflags=@($RoutingXML.routing.preamble.flags) | where {$_.name -eq "clientflags"}

			#If our clientflags value says simultaneous ringing is set up, let's fill a variable with
			# the resulting number, otherwise leave it blank.
			$simringto=""
			if ($clientflags.value -eq "simultaneous_ring")
			{
				$tempholder=@($RoutingXML.routing.preamble.list) | where {$_.name -eq "simultaneous_ring"}
				$simringto=$tempholder.target.uri
			}
	
			#If our clientflags value says forwarding is set up, let's fill a variable with
			# the results, otherwise leave it blank.
			$forwardto=""
			if ($clientflags.value -eq "enablecf forward_immediate")
			{
				$tempholder=@($RoutingXML.routing.preamble.list) | where {$_.name -eq "forwardto"}
				$forwardto=$tempholder.target.uri
				$NoVarAnswerTo=$tempholder.target.uri
			}

			#If our clientflags value says send to voicemail on no answer is set up, let's fill a variable with
			# the results, otherwise leave it blank.  The results are stored in the forward section of the XML.
			if ($clientflags.value -eq "enablecf")
			{
				$tempholder=@($RoutingXML.routing.preamble.list) | where {$_.name -eq "forwardto"}
				$NoVarAnswerTo=$tempholder.target.uri
			}

			#If our clientflags value says "forward immediate" without enablecf, we're likely just forwarding to voicemail
			#The noanswer variable is set to VoiceMail by default.
			if ($clientflags.value -eq "enablecf")
			{
				$tempholder=@($RoutingXML.routing.preamble.list) | where {$_.name -eq "forwardto"}
				if ($tempholder.target.uri) { $NoVarAnswerTo=$tempholder.target.uri }
			}
	
			#Let's get our delegate list, regardless if they're used.
			$delegate_receivecall_list=""
			$tempholder=@($RoutingXML.routing.preamble.list) | where {$_.name -eq "delegates"}
			foreach ($x in  $tempholder.target)
			{
				if ($delegate_receivecall_list.length -gt 0) { $delegate_receivecall_list += "; " }
				$delegate_receivecall_list += $x.uri
			} 

			#Let's get our team group list, regardless if they're used.
			$teamvargrouplist=""
			$tempholder=@($RoutingXML.routing.preamble.list) | where {$_.name -eq "team"}
			foreach ($x in  $tempholder.target)
			{
				if ($teamvargrouplist.length -gt 0) { $teamvargrouplist += "; " }
				$teamvargrouplist += $x.uri
			} 

			#Let's get our seconds until unanswered time
			$NoVarAnswerSeconds=""
			$tempholder=@($RoutingXML.routing.preamble.wait) | where {$_.name -eq "total"}
			$NoVarAnswerSeconds=$tempholder.seconds

			#Let's get our seconds until call rings delegates or team group
			$DelegateOrGroupAnswerSeconds=""
			$tempholder=@($RoutingXML.routing.preamble.wait) | where {$_.name -eq "user"}
			$DelegateOrGroupAnswerSeconds=$tempholder.seconds

			#Check if Working Hours is Set in the Flags
			if ($clientflags.value -like "*work_hours*") {$AppliedDuringWork = "True"} else {$AppliedDuringWork = "False"}
		
			#Check if Forwarding or SimRing To Delegates is Set in the Flags
			if (($clientflags.value -like "*delegate_ring*") -and ($clientflags.value -like "*skip_primary*")) 
				{
					$ForwardTo = "Delegates"
					$simringto = ""
				} 
			if (($clientflags.value -like "*delegate_ring*") -and ($clientflags.value -notlike "*skip_primary*")) 
				{
					$ForwardTo = ""
					$simringto = "Delegates"
				}

		#Check if Forwarding or SimRing To Team Group is Set in the Flags
		if ($clientflags.value -like "*team_ring*")
			{
				$ForwardTo = ""
				$simringto = "Team Call Group"
			} 			 

			$global:ForwardingInfoArray += New-Object PSCustomObject -Property @{
 			"SIP Address" = $SipName
			Action = $clientflags.value
			"Applied During Working Hours" = $AppliedDuringWork
			"Forwarding To" = $forwardto
			"Simutaneous Ring To" = $simringto
			"No Answer To" = $NoVarAnswerTo
			"No Answer In Seconds" = $NoVarAnswerSeconds
			"Seconds Until Delegate or Group Rings" = $DelegateOrGroupAnswerSeconds
			"All Delegates" = ($AllDelegates -join ', ')
			"Delegates that Receive Calls" = $delegate_receivecall_list
			"Team Group" = $teamvargrouplist
			}
		}	
	}
}


	If(Test-Path $TempFolder)
	{
	Remove-Item "$TempFolder" -ErrorAction:Stop -recurse
	}

}


Function WelcomeForm()
{
	$objForm = New-Object System.Windows.Forms.Form 
	$objForm.Text = "Lync 2013 Call Forwarding Informational Utility"
	$objForm.Size = New-Object System.Drawing.Size(640,300) 
	$objForm.StartPosition = "CenterScreen"
	$ObjForm.Add_SizeChanged($CAC_FormSizeChanged)
	$ObjForm.BackColor = "#FFFFFFFF"
	$objForm.Icon = $Global:SkypeAdminIcon
	$objForm.KeyPreview = $True

	$TitleLabel = New-Object System.Windows.Forms.Label
	$TitleLabel.Location = New-Object System.Drawing.Size(10,10) 
	$TitleLabel.Size = New-Object System.Drawing.Size(600,60) 
	$TitleLabel.Text = "The purpose of this tool is to give you an easy front end for reviewing the call forwarding settings for users within your Lync 2013 environment.  Additional settings have been added to Skype for Business and as such, that will be delivered as a seperate application. Please use the Q/A section of the TechNet gallery to suggest features you would like to see.  As with any script found on the Internet, use only at your own risk."
	$objForm.Controls.Add($TitleLabel) 

	$PoolDropDownComboBox = new-object System.Windows.Forms.ComboBox
	$PoolDropDownComboBox.Location = New-Object System.Drawing.Size(10,80) 
	$PoolDropDownComboBox.Size = New-Object System.Drawing.Size(600,25) 
	$PoolDropDownComboBox.Anchor = 'Top, Left, Right'
	$objForm.Controls.Add($PoolDropDownComboBox) 

	$AddCAP_PoolArray=get-cspool | foreach {if ($_.Services -like "Registrar*") {$_.Identity}}
	$PoolDropDownComboBox.Items.Clear()
	foreach ($x in $AddCAP_PoolArray) 
	{
		[void]$PoolDropDownComboBox.Items.Add($x)
	}
	$PoolDropDownComboBox.SelectedIndex=0

	$LoadDataButton = New-Object System.Windows.Forms.Button
	$LoadDataButton.Location = New-Object System.Drawing.Size(10,120)
	$LoadDataButton.Size = New-Object System.Drawing.Size(300,40)
	$LoadDataButton.Text = "Load Data From Selected Pool"
	$LoadDataButton.Add_Click({
		$LoadDataButton.Text = "Loading..."
		$LoadDataButton.Enabled=$False
		LoadDataIntoArray
		$LoadDataButton.Text = "Load Data From Selected Pool"
		$LoadDataButton.Enabled=$True
		$DisplayInGridViewButton.Enabled=$True
		$ExportToCSVButton.Enabled = $true
	})
	$LoadDataButton.Anchor = 'Bottom, Left'
	$objForm.Controls.Add($LoadDataButton)

	$CancelButton = New-Object System.Windows.Forms.Button
	$CancelButton.Location = New-Object System.Drawing.Size(310,180)
	$CancelButton.Size = New-Object System.Drawing.Size(300,40)
	$CancelButton.Text = "Quit"
	$CancelButton.Add_Click({	$objForm.Close()	})
	$CancelButton.Anchor = 'Bottom, Right'
	$objForm.Controls.Add($CancelButton)

	$DisplayInGridViewButton = New-Object System.Windows.Forms.Button
	$DisplayInGridViewButton.Location = New-Object System.Drawing.Size(300,120)
	$DisplayInGridViewButton.Size = New-Object System.Drawing.Size(310,40)
	$DisplayInGridViewButton.Enabled=$false
	$DisplayInGridViewButton.Text = "Display Data In Out-GridView"
	$DisplayInGridViewButton.Add_Click({
		$global:ForwardingInfoArray  |Select "SIP Address", Action ,"Applied During Working Hours","Forwarding To", "Simutaneous Ring To", "No Answer To", "No Answer In Seconds","Seconds Until Delegate or Group Rings", "All Delegates","Delegates that Receive Calls", "Team Group" |Out-GridView -Title ”Show All Call Forwarding Information For Selected Pool”
	})
	$DisplayInGridViewButton.Anchor = 'Bottom, Left'
	$objForm.Controls.Add($DisplayInGridViewButton)

	$ExportToCSVButton = New-Object System.Windows.Forms.Button
	$ExportToCSVButton.Location = New-Object System.Drawing.Size(10,180)
	$ExportToCSVButton.Size = New-Object System.Drawing.Size(300,40)
	$ExportToCSVButton.Text = "Export to CSV"
	$ExportToCSVButton.Enabled = $false
	$ExportToCSVButton.Add_Click({
		$SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
		$SaveFileDialog.filter = "CSV Export files (*.csv)| *.csv"
		[void] $SaveFileDialog.ShowDialog()
		if ($SaveFileDialog.filename.length -gt 0) 
		{
			$global:ForwardingInfoArray  |Select "SIP Address", Action,"Applied During Working Hours", "Forwarding To", "Simutaneous Ring To", "No Answer To", "No Answer In Seconds","Seconds Until Delegate or Group Rings","All Delegates", "Delegates that Receive Calls", "Team Group" |Export-CSV -path $SaveFileDialog.filename -NoTypeInformation
		}
	})
	$ExportToCSVButton.Anchor = 'Bottom, Left'
	$objForm.Controls.Add($ExportToCSVButton)

	#SkypeAdmin LinkLabel
	$SkypeAdminLinkLabel = New-Object System.Windows.Forms.LinkLabel
	$SkypeAdminLinkLabel.Location = New-Object System.Drawing.Size(10,238) 
	$SkypeAdminLinkLabel.Size = New-Object System.Drawing.Size(150,20)
	$SkypeAdminLinkLabel.text = "http://www.SkypeAdmin.com"
	$SkypeAdminLinkLabel.add_Click({Start-Process $SkypeAdminLinkLabel.text})
	$SkypeAdminLinkLabel.Anchor = 'Bottom, Left'
	$objForm.Controls.Add($SkypeAdminLinkLabel)

	$objForm.Add_Shown({$objForm.Activate()})
	[void] $objForm.ShowDialog()

}

write "Loading... Please be patient..."

$Global:SkypeAdminIcon = [System.Convert]::FromBase64String('
AAABAAEAJiEAAAEAIADIFAAAFgAAACgAAAAmAAAAQgAAAAEAIAAAAAAAmBMAAAAAAAAAAAAAAAAAAAAA
AADMKzP/zFVm/8xVM//MKzP/zFUz/8xVZv/MKzP/zFVm/8xVM//MK2b/zFUz/8xVM//MKzP/zFUz/8wr
M//MVTP/zFUz/8xVM//MVTP/zCsz/8xVM//MK2b/zFUz/8xVZv/MKzP/zFUz/8xVM//MKzP/zFUz/8xV
Zv/MKzP/zFUz/8xVM//MKzP/zFUz/8xVM//MKzP/zFUz/8xVM//MVTP/zCsz/8xVZv/MVTP/zCsz/8xV
M//MVTP/zCsz/8xVM//MVTP/zCtm/8xVM//MVTP/zFVm/8wrM//MVWb/zCsz/8xVZv/MVTP/zFUz/8xV
M//MKzP/zFUz/8xVM//MK2b/zFUz/8xVM//MKzP/zFUz/8xVM//MVWb/zCsz/8xVM//MK2b/zFUz/8xV
Zv/MVTP/zFUz/8wrZv/MVTP/zFUz/8wrM//MVTP/zFVm/8wrM//MVTP/zFVm/8wrM//MVTP/zFVm/8wr
M//MVTP/zCsz/8xVM//MVTP/zFUz/8wrM//MVWb/zCsz/8xVM//MK2b/zFUz/8xVM//MK2b/zFUz/8xV
M//MK2b/zFUz/8wrM//MVWb/zFUz/8xVM//MVTP/zCsz/8xVM//MVTP/zFUz/8wrM//MVWb/zFUz/8wr
M//MVTP/zFUz/8wrM//MVTP/zFUz/8xVM//MKzP/zFUz/8xVZv/MVTP/zCsz/8xVM//MKzP/zFUz/8xV
M//MVTP/zFVm/8xVM//MKzP/zFUz/8xVM//MKzP/zFUz/8xVM//MVTP/zFUz/8wrM//MVTP/zCtm/8xV
M//MVTP/zCtm/8xVM//MK2b/zFUz/8xVM//MgDP/////////////////////////////////zCuZ/8xV
M//MVTP/zCsz////zP///////////////////////////8xVmf/MKzP/zFUz////zP//////////////
/////////////8xVmf/MKzP/zFVm/8xVM//MVTP/zCsz/8xVM//MVTP/zFUz/8xVM//MKzP////M////
/////////////////////////////////////////////8yAzP/MVTP//6pm////////////////////
////////zNX//8xVM//MVTP//9WZ////////////////////////////zFWZ/8xVM//MVTP/zCsz/8xV
Zv/MVTP/zCtm/8xVM//MKzP/zFUz//+qZv//////////////////////////////////////////////
/////////////8yqzP/MVTP////M////////////////////////////zFXM/8wrM///qmb/////////
///////////////////MgMz/zFUz/8wrZv/MVTP/zFUz/8wrM//MVTP/zFUz/8xVM//MVTP//6qZ////
/////////////////////////////////////////////////////////////8yAzP//qmb/////////
///////////////////Mqsz/zFUz//+AM////////////////////////////8yq///MVTP/zFUz/8wr
M//MVWb/zFUz/8wrM//MVWb/zCtm/8xVM///qmb////////////////////////////MVZn/zCsz////
zP///////////////////////9X//8xVZv///8z/////////////////////////////////////////
////////////////////////zP///8wrZv/MVWb/zFUz/8xVM//MKzP/zFUz/8xVM//MVTP/zCsz//9V
M////////////////////////////8yAzP/MVTP//6pm////////////////////////////zFWZ//+q
Zv//////////////////////////////////////////////////////////////////////zFVm/8wr
M//MVTP/zCtm/8xVM//MVWb/zCsz/8xVM//MVTP/zFUz////zP//////////////////////zNX//8xV
M///VTP////M///////////////////////Mqsz/zFUz////zP//////////////////////////////
///////////////////////////////////MVZn/zFVm/8xVM//MVTP/zCsz/8xVM//MVTP/zFUz/8wr
M//MVWb//6pm////////////////////////////zCuZ/8yAM//////////////////////////////V
///MVWb//9WZ/////////////////////////////////////////////////////////////////8yA
zP/MVTP/zCsz/8xVZv/MVTP/zCtm/8xVM//MK2b/zFUz/8xVM//MK2b/zFUz/8xVM//MK2b/zFUz/8xV
M//MVTP//9WZ////////////////////////////zP///8xVmf//VTP////M////////////////////
///MVZn/zFUz///Vmf//////////////////////zKr//8wrM//MVTP/zFUz/8wrM//MVTP/zFUz/8xV
M//MVTP/zCsz/8xVM//MVTP/zCsz/8xVM//MKzP/zFVm///Vmf//////////////////////////////
////////zFWZ/8xVM///1Zn//////////////////////8yq///MVTP//9WZ////////////////////
///M1f//zFUz/8xVM//MK2b/zFUz/8xVM//MKzP/zFUz/8wrZv/MVTP/zFUz/8wrZv/MVTP/zFVm/8xV
M///1Zn////////////////////////////////////////////MVZn/zFUz/8xVM///////////////
/////////////8xVZv//gDP//////////////////////8z////MVZn/zCsz/8xVM//MVTP/zCtm/8xV
M//MVTP/zFUz/8wrM//MVWb/zFUz/8wrM//MVTP//9WZ////////////////////////////////////
////////zKr//8wrM//MVTP/zFVm///Vmf//////////////////////zKr//8xVM///////////////
/////////////8xVmf/MVWb/zFUz/8wrM//MVTP/zFUz/8xVM//MK2b/zFUz/8xVM//MKzP/zFUz///V
mf///////////////////////////////////////////8zV///MVTP/zFVm/8wrM//MVTP//4Az////
////////////////////////zCtm////mf//////////////////////zIDM/8wrM//MVTP/zFUz/8wr
Zv/MVTP/zFUz/8xVM//MKzP/zFVm/8xVM///KzP////M////////////////////////////////////
///M1f//zFVm/8wrM//MVTP/zFUz/8wrZv/MVTP//9XM///////////////////////MgMz//6qZ////
///////////////////Mqsz/zFUz/8wrZv/MVTP/zFUz/8xVM//MKzP/zFVm/8xVM//MKzP/zFUz/8xV
M////8z/////////////////////////////////zNX//8wrM//MVTP/zFUz/8wrZv/MVTP/zFUz/8xV
M///gDP//////////////////////8z/////gDP////////////////////////V///MKzP/zFUz/8xV
M//MK2b/zFUz/8xVM//MVTP/zCsz/8xVZv/MVTP/zCsz////zP///////////////////////////8zV
///MVTP/zFUz/8wrM//MVTP/zFUz/8wrM//MVTP/zCsz/8xVM////5n//////////////////////8yA
zP///8z/////////////////zP///8xVZv/MKzP/zFUz/8xVM//MKzP/zCsz/8xVZv/MVTP/zCsz/8xV
M//MVTP//6qZ////////////////////////////zFWZ//9VM////////////////////////////8yq
///MVTP/zCtm//+AM////////////////////////9X/////zP//////////////////////zCuZ/8xV
M//MKzP/zFVm/8xVM//MVTP/zFUz/8wrM//MVWb/zFUz/8wrM///qjP/////////////////////////
///MVZn/zFUz///Vmf///////////////////////9X//8xVZv/MVTP/zFUz////zP//////////////
/////////6rM///////////////////////MgMz/zFUz/8xVM//MKzP/zFUz/8wrM//MVWb/zFUz/8wr
M//MVWb/zFUz/8wrM////8z//////////////////////8yq///MVTP//6pm////////////////////
///M////zFWZ/8wrM//MVTP//6pm/////////////////////////////////////////////////8yq
///MVTP/zCsz/8xVZv/MVTP/zFUz/8wrM//MVTP/zFUz/8wrM//MVTP/zFVm//+qZv//////////////
///////////////////////////////////////////////////MVZn/zFUz/8xVZv/MKzP////M////
////////////////////////////////////////zKr//8xVM//MVTP/zCsz/8xVM//MVWb/zFUz/8wr
Zv/MVTP/zFVm/8wrM//MVTP/zFUz//+qmf//////////////////////////////////////////////
/////////////8yAzP/MVTP/zCsz/8xVM///qmb/////////////////////////////////////////
///M////zCtm/8xVM//MK2b/zFUz/8xVM//MKzP/zFUz/8xVM//MKzP/zFUz/8wrZv/MVTP/zFUz//+q
Zv//////////////////////////////////////////////////////zCtm/8xVM//MVWb/zCsz/8xV
Zv///8z////////////////////////////////////////////MVWb/zFUz/8xVM//MVTP/zCsz/8xV
M//MVWb/zCsz/8xVZv/MVTP/zFUz/8xVM//MKzP/zFUz/8xVM///qmb/////////////////////////
////////zIDM/8wrM//MVTP/zFUz/8wrM//MVTP/zFUz//+qZv//////////////////////////////
/////////////8xVzP/MVTP/zCtm/8xVM//MVTP/zCsz/8xVM//MVTP/zCsz/8xVM//MK2b/zFUz/8xV
Zv/MKzP/zFUz/8xVM//MKzP/zFVm/8xVM//MK2b/zFUz/8xVM//MKzP/zFUz/8xVZv/MKzP/zFVm/8xV
M//MKzP/zFUz/8xVM//MKzP/zFUz/8xVM//MVWb/zCsz/8xVM//MVTP/zCsz/8xVM//MVTP/zCsz/8xV
Zv/MVTP/zFUz/8wrM//MVWb/zFUz/8xVM//MKzP/zFUz/8xVZv/MKzP/zFVm/8xVM//MKzP/zFUz/8xV
M//MK2b/zFUz/8xVZv/MKzP/zFUz/8xVM//MVTP/zCtm/8xVM//MVWb/zCsz/8xVM//MVWb/zCsz/8xV
M//MVTP/zCsz/8xVM//MVWb/zCsz/8xVZv/MVTP/zFUz/8wrM//MVWb/zFUz/8wrM//MVTP/zCtm/8xV
M//MVTP/zCsz/8xVM//MVTP/zCsz/8xVZv/MKzP/zFUz/8xVM//MKzP/zFUz/8xVM//MK2b/zFUz/8wr
M//MVTP/zFUz/8wrM//MVTP/zFVm/8wrM//MVTP/zCtm/8xVM//MVWb/zCsz/8xVM//MVTP/zCsz/8xV
M//MKzP/zFUz/8xVM//MKzP/zFVm/8xVM//MVTP/zFUz/8wrM//MVTP/zFUz/8wrZv/MVTP/zFUz/8xV
M//MVTP/zCsz/8xVM//MVWb/zCsz/8xVM//MVTP/zFUz/8xVM//MKzP/zFVm/8xVM//MKzP/zFUz/8xV
M//MVTP/zFUz/8wrM//MVTP/zFUz/8wrZv/MVTP/zFUz/8xVM//MK2b/zFUz/8xVZv/MKzP/zFUz/8wr
Zv/MVTP/zFVm/8wrM//MVWb/zFUz/8wrM//MVWb/zCsz/8xVZv/MVTP/zCtm/8xVM//MVTP/zCtm/8xV
M//MK2b/zFUz/8xVZv/MKzP/zFUz/8xVZv/MKzP/zFVm/8wrM//MVWb/zFUz/8wrM//MVWb/zFUz/8wr
M//MVWb/zFUz/8xVM//MVTP/zCsz/8xVM//MVTP/zFUz/8wrM//MVTP/zFUz/8xVM//MKzP/zFUz/8xV
M//MVTP/zCsz/8xVM//MVTP/zFUz/8wrM//MVTP/zFUz/8xVM//MKzP/zFUz/8xVM//MVTP/zCsz/8xV
M//MVTP/zFUz/8wrM//MVTP/zFUz/8xVM//MKzP/zFUz/8xVM/8AAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAA=
')
Import-Module Lync
$global:ForwardingInfoArray = @()
WelcomeForm


# SIG # Begin signature block
# MIIcagYJKoZIhvcNAQcCoIIcWzCCHFcCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUBn1p5tdBzYPFOUJm2dRCf7C4
# J6aggheZMIIFIjCCBAqgAwIBAgIQCtdQcWk4+bZhH01n2swNajANBgkqhkiG9w0B
# AQsFADByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFz
# c3VyZWQgSUQgQ29kZSBTaWduaW5nIENBMB4XDTE1MDYwOTAwMDAwMFoXDTE2MDYx
# MzEyMDAwMFowaTELMAkGA1UEBhMCVVMxETAPBgNVBAgTCElsbGlub2lzMRMwEQYD
# VQQHEwpQbGFpbmZpZWxkMRgwFgYDVQQKEw9DaGFybGVzIENhcmFnb2wxGDAWBgNV
# BAMTD0NoYXJsZXMgQ2FyYWdvbDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC
# ggEBAMlS7OcIyDJbfx/iE8q1z8h9uzjcVY0DXtiVS9Ep0SV9p5W6EP6S6bFWLmn+
# iwoaPe7eOyxF+6MACDkcewrewy7EfGln+/b9CK+yjzXvPfSwKukNemcdRdOpwjxl
# 0N+VXVRaed1FaL5+Tar1vvgIqEJzTncTukoGlEK4MyXX9Oz/fbKn8/ALGtr3LggG
# WxkbKL3mR5Cd3KgXBnLUatUL5iH+HeXMKoHCOaaYbccdVyK/1McMrJrTQspjdavJ
# Nv0VZEQXVPRAT1v2xekcg/cIqQJTvjVfQi9CMQaEUyjpK7BJrMwqDkHBUt5ImswH
# StT0u9uJ038bqHxxT/yGEHq7DmECAwEAAaOCAbswggG3MB8GA1UdIwQYMBaAFFrE
# uXsqCqOl6nEDwGD5LfZldQ5YMB0GA1UdDgQWBBTIhd3RKKKuqHZ9t6u8MX7LUGle
# pDAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYBBQUHAwMwdwYDVR0fBHAw
# bjA1oDOgMYYvaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL3NoYTItYXNzdXJlZC1j
# cy1nMS5jcmwwNaAzoDGGL2h0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9zaGEyLWFz
# c3VyZWQtY3MtZzEuY3JsMEIGA1UdIAQ7MDkwNwYJYIZIAYb9bAMBMCowKAYIKwYB
# BQUHAgEWHGh0dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMwgYQGCCsGAQUFBwEB
# BHgwdjAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tME4GCCsG
# AQUFBzAChkJodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRTSEEy
# QXNzdXJlZElEQ29kZVNpZ25pbmdDQS5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG
# 9w0BAQsFAAOCAQEAHPZYGlEZ/0dUvAlE1nLUQfFuDnzFpMux3PiWEF5fyG4SnpQm
# aaPYy+OIVlMUAhOQljRX1X1FofRGa9o3KcyXL8466AfO3UD3jL31zo5SEtjlahyg
# i/+oyJRJkM9tGl7ME050T4V+kacf3yDHmJ0ethRda905kv4Kt9PWFvcweIrG6WQl
# YjFG5Zaa3tHkRHyJjshUkEbByhQuZVj89KmoHMEg1OtVK691eNAd3qqHCZRqValf
# HJkqOl1nnaLfjlUgXlCpJIMOoPlCAfpe773qzdpGoB4Y0BioyaKEuv07/1jKoaS+
# FgYyD3+5H6mTHyMH7It8OEbmdqODnduj8NKPgjCCBTAwggQYoAMCAQICEAQJGBtf
# 1btmdVNDtW+VUAgwDQYJKoZIhvcNAQELBQAwZTELMAkGA1UEBhMCVVMxFTATBgNV
# BAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEkMCIG
# A1UEAxMbRGlnaUNlcnQgQXNzdXJlZCBJRCBSb290IENBMB4XDTEzMTAyMjEyMDAw
# MFoXDTI4MTAyMjEyMDAwMFowcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lD
# ZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGln
# aUNlcnQgU0hBMiBBc3N1cmVkIElEIENvZGUgU2lnbmluZyBDQTCCASIwDQYJKoZI
# hvcNAQEBBQADggEPADCCAQoCggEBAPjTsxx/DhGvZ3cH0wsxSRnP0PtFmbE620T1
# f+Wondsy13Hqdp0FLreP+pJDwKX5idQ3Gde2qvCchqXYJawOeSg6funRZ9PG+ykn
# x9N7I5TkkSOWkHeC+aGEI2YSVDNQdLEoJrskacLCUvIUZ4qJRdQtoaPpiCwgla4c
# SocI3wz14k1gGL6qxLKucDFmM3E+rHCiq85/6XzLkqHlOzEcz+ryCuRXu0q16XTm
# K/5sy350OTYNkO/ktU6kqepqCquE86xnTrXE94zRICUj6whkPlKWwfIPEvTFjg/B
# ougsUfdzvL2FsWKDc0GCB+Q4i2pzINAPZHM8np+mM6n9Gd8lk9ECAwEAAaOCAc0w
# ggHJMBIGA1UdEwEB/wQIMAYBAf8CAQAwDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQM
# MAoGCCsGAQUFBwMDMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDov
# L29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5k
# aWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MIGBBgNVHR8E
# ejB4MDqgOKA2hjRodHRwOi8vY3JsNC5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1
# cmVkSURSb290Q0EuY3JsMDqgOKA2hjRodHRwOi8vY3JsMy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsME8GA1UdIARIMEYwOAYKYIZIAYb9
# bAACBDAqMCgGCCsGAQUFBwIBFhxodHRwczovL3d3dy5kaWdpY2VydC5jb20vQ1BT
# MAoGCGCGSAGG/WwDMB0GA1UdDgQWBBRaxLl7KgqjpepxA8Bg+S32ZXUOWDAfBgNV
# HSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzANBgkqhkiG9w0BAQsFAAOCAQEA
# PuwNWiSz8yLRFcgsfCUpdqgdXRwtOhrE7zBh134LYP3DPQ/Er4v97yrfIFU3sOH2
# 0ZJ1D1G0bqWOWuJeJIFOEKTuP3GOYw4TS63XX0R58zYUBor3nEZOXP+QsRsHDpEV
# +7qvtVHCjSSuJMbHJyqhKSgaOnEoAjwukaPAJRHinBRHoXpoaK+bp1wgXNlxsQyP
# u6j4xRJon89Ay0BEpRPw5mQMJQhCMrI2iiQC/i9yfhzXSUWW6Fkd6fp0ZGuy62ZD
# 2rOwjNXpDd32ASDOmTFjPQgaGLOBm0/GkxAG/AeB+ova+YJJ92JuoVP6EpQYhS6S
# kepobEQysmah5xikmmRR7zCCBmowggVSoAMCAQICEAMBmgI6/1ixa9bV6uYX8GYw
# DQYJKoZIhvcNAQEFBQAwYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0
# IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNl
# cnQgQXNzdXJlZCBJRCBDQS0xMB4XDTE0MTAyMjAwMDAwMFoXDTI0MTAyMjAwMDAw
# MFowRzELMAkGA1UEBhMCVVMxETAPBgNVBAoTCERpZ2lDZXJ0MSUwIwYDVQQDExxE
# aWdpQ2VydCBUaW1lc3RhbXAgUmVzcG9uZGVyMIIBIjANBgkqhkiG9w0BAQEFAAOC
# AQ8AMIIBCgKCAQEAo2Rd/Hyz4II14OD2xirmSXU7zG7gU6mfH2RZ5nxrf2uMnVX4
# kuOe1VpjWwJJUNmDzm9m7t3LhelfpfnUh3SIRDsZyeX1kZ/GFDmsJOqoSyyRicxe
# KPRktlC39RKzc5YKZ6O+YZ+u8/0SeHUOplsU/UUjjoZEVX0YhgWMVYd5SEb3yg6N
# p95OX+Koti1ZAmGIYXIYaLm4fO7m5zQvMXeBMB+7NgGN7yfj95rwTDFkjePr+hmH
# qH7P7IwMNlt6wXq4eMfJBi5GEMiN6ARg27xzdPpO2P6qQPGyznBGg+naQKFZOtkV
# CVeZVjCT88lhzNAIzGvsYkKRrALA76TwiRGPdwIDAQABo4IDNTCCAzEwDgYDVR0P
# AQH/BAQDAgeAMAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# ggG/BgNVHSAEggG2MIIBsjCCAaEGCWCGSAGG/WwHATCCAZIwKAYIKwYBBQUHAgEW
# HGh0dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMwggFkBggrBgEFBQcCAjCCAVYe
# ggFSAEEAbgB5ACAAdQBzAGUAIABvAGYAIAB0AGgAaQBzACAAQwBlAHIAdABpAGYA
# aQBjAGEAdABlACAAYwBvAG4AcwB0AGkAdAB1AHQAZQBzACAAYQBjAGMAZQBwAHQA
# YQBuAGMAZQAgAG8AZgAgAHQAaABlACAARABpAGcAaQBDAGUAcgB0ACAAQwBQAC8A
# QwBQAFMAIABhAG4AZAAgAHQAaABlACAAUgBlAGwAeQBpAG4AZwAgAFAAYQByAHQA
# eQAgAEEAZwByAGUAZQBtAGUAbgB0ACAAdwBoAGkAYwBoACAAbABpAG0AaQB0ACAA
# bABpAGEAYgBpAGwAaQB0AHkAIABhAG4AZAAgAGEAcgBlACAAaQBuAGMAbwByAHAA
# bwByAGEAdABlAGQAIABoAGUAcgBlAGkAbgAgAGIAeQAgAHIAZQBmAGUAcgBlAG4A
# YwBlAC4wCwYJYIZIAYb9bAMVMB8GA1UdIwQYMBaAFBUAEisTmLKZB+0e36K+Vw0r
# ZwLNMB0GA1UdDgQWBBRhWk0ktkkynUoqeRqDS/QeicHKfTB9BgNVHR8EdjB0MDig
# NqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURD
# QS0xLmNybDA4oDagNIYyaHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# QXNzdXJlZElEQ0EtMS5jcmwwdwYIKwYBBQUHAQEEazBpMCQGCCsGAQUFBzABhhho
# dHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQQYIKwYBBQUHMAKGNWh0dHA6Ly9jYWNl
# cnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRENBLTEuY3J0MA0GCSqG
# SIb3DQEBBQUAA4IBAQCdJX4bM02yJoFcm4bOIyAPgIfliP//sdRqLDHtOhcZcRfN
# qRu8WhY5AJ3jbITkWkD73gYBjDf6m7GdJH7+IKRXrVu3mrBgJuppVyFdNC8fcbCD
# lBkFazWQEKB7l8f2P+fiEUGmvWLZ8Cc9OB0obzpSCfDscGLTYkuw4HOmksDTjjHY
# L+NtFxMG7uQDthSr849Dp3GdId0UyhVdkkHa+Q+B0Zl0DSbEDn8btfWg8cZ3BigV
# 6diT5VUW8LsKqxzbXEgnZsijiwoc5ZXarsQuWaBh3drzbaJh6YoLbewSGL33VVRA
# A5Ira8JRwgpIr7DUbuD0FAo6G+OPPcqvao173NhEMIIGzTCCBbWgAwIBAgIQBv35
# A5YDreoACus/J7u6GzANBgkqhkiG9w0BAQUFADBlMQswCQYDVQQGEwJVUzEVMBMG
# A1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQw
# IgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMDYxMTEwMDAw
# MDAwWhcNMjExMTEwMDAwMDAwWjBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGln
# aUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhE
# aWdpQ2VydCBBc3N1cmVkIElEIENBLTEwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAw
# ggEKAoIBAQDogi2Z+crCQpWlgHNAcNKeVlRcqcTSQQaPyTP8TUWRXIGf7Syc+BZZ
# 3561JBXCmLm0d0ncicQK2q/LXmvtrbBxMevPOkAMRk2T7It6NggDqww0/hhJgv7H
# xzFIgHweog+SDlDJxofrNj/YMMP/pvf7os1vcyP+rFYFkPAyIRaJxnCI+QWXfaPH
# Q90C6Ds97bFBo+0/vtuVSMTuHrPyvAwrmdDGXRJCgeGDboJzPyZLFJCuWWYKxI2+
# 0s4Grq2Eb0iEm09AufFM8q+Y+/bOQF1c9qjxL6/siSLyaxhlscFzrdfx2M8eCnRc
# QrhofrfVdwonVnwPYqQ/MhRglf0HBKIJAgMBAAGjggN6MIIDdjAOBgNVHQ8BAf8E
# BAMCAYYwOwYDVR0lBDQwMgYIKwYBBQUHAwEGCCsGAQUFBwMCBggrBgEFBQcDAwYI
# KwYBBQUHAwQGCCsGAQUFBwMIMIIB0gYDVR0gBIIByTCCAcUwggG0BgpghkgBhv1s
# AAEEMIIBpDA6BggrBgEFBQcCARYuaHR0cDovL3d3dy5kaWdpY2VydC5jb20vc3Ns
# LWNwcy1yZXBvc2l0b3J5Lmh0bTCCAWQGCCsGAQUFBwICMIIBVh6CAVIAQQBuAHkA
# IAB1AHMAZQAgAG8AZgAgAHQAaABpAHMAIABDAGUAcgB0AGkAZgBpAGMAYQB0AGUA
# IABjAG8AbgBzAHQAaQB0AHUAdABlAHMAIABhAGMAYwBlAHAAdABhAG4AYwBlACAA
# bwBmACAAdABoAGUAIABEAGkAZwBpAEMAZQByAHQAIABDAFAALwBDAFAAUwAgAGEA
# bgBkACAAdABoAGUAIABSAGUAbAB5AGkAbgBnACAAUABhAHIAdAB5ACAAQQBnAHIA
# ZQBlAG0AZQBuAHQAIAB3AGgAaQBjAGgAIABsAGkAbQBpAHQAIABsAGkAYQBiAGkA
# bABpAHQAeQAgAGEAbgBkACAAYQByAGUAIABpAG4AYwBvAHIAcABvAHIAYQB0AGUA
# ZAAgAGgAZQByAGUAaQBuACAAYgB5ACAAcgBlAGYAZQByAGUAbgBjAGUALjALBglg
# hkgBhv1sAxUwEgYDVR0TAQH/BAgwBgEB/wIBADB5BggrBgEFBQcBAQRtMGswJAYI
# KwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3
# aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9v
# dENBLmNydDCBgQYDVR0fBHoweDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQu
# Y29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDA6oDigNoY0aHR0cDovL2Ny
# bDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDAdBgNV
# HQ4EFgQUFQASKxOYspkH7R7for5XDStnAs0wHwYDVR0jBBgwFoAUReuir/SSy4Ix
# LVGLp6chnfNtyA8wDQYJKoZIhvcNAQEFBQADggEBAEZQPsm3KCSnOB22WymvUs9S
# 6TFHq1Zce9UNC0Gz7+x1H3Q48rJcYaKclcNQ5IK5I9G6OoZyrTh4rHVdFxc0ckeF
# lFbR67s2hHfMJKXzBBlVqefj56tizfuLLZDCwNK1lL1eT7EF0g49GqkUW6aGMWKo
# qDPkmzmnxPXOHXh2lCVz5Cqrz5x2S+1fwksW5EtwTACJHvzFebxMElf+X+EevAJd
# qP77BzhPDcZdkbkPZ0XN1oPt55INjbFpjE/7WeAjD9KqrgB87pxCDs+R1ye3Fu4P
# w718CqDuLAhVhSK46xgaTfwqIa1JMYNHlXdx3LEbS0scEJx3FMGdTy9alQgpECYx
# ggQ7MIIENwIBATCBhjByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQg
# SW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2Vy
# dCBTSEEyIEFzc3VyZWQgSUQgQ29kZSBTaWduaW5nIENBAhAK11BxaTj5tmEfTWfa
# zA1qMAkGBSsOAwIaBQCgeDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqG
# SIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3
# AgEVMCMGCSqGSIb3DQEJBDEWBBTffx7bpxUd1nF3DQkL2Wy+fQ53PjANBgkqhkiG
# 9w0BAQEFAASCAQBb9P01ahyvo6jSBrjQs9fLOn9t1sAjgJIkQWFYd9EuL0t1qyvY
# 68GFXT/z5UyeP/blumqH3mnln+3YIcUXIumkWaDQcu4Dkc6FY3orJTD/0vzMrHdk
# jOPlUWFvVsn6hU1P05vBT3aIPIHRRBbcArc6qIBFgAIq9MKnsdLb2gwlxMSN8ghh
# Ze4xFUvcwBXm1waS90THGMSJ7AqbsU6pGPXJ7cpb+TUua3JyyJy4pi+pSOLJglrK
# snVIAOxbKZFXAylgJelnceZ6RmqgYmnFzA4Vhd+UkbP6/lvyj3wJLWFfff4CvUY0
# aCoUFUMsY9SnXi7zgCl7hHwsPApiHVuciQdboYICDzCCAgsGCSqGSIb3DQEJBjGC
# AfwwggH4AgEBMHYwYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IElu
# YzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQg
# QXNzdXJlZCBJRCBDQS0xAhADAZoCOv9YsWvW1ermF/BmMAkGBSsOAwIaBQCgXTAY
# BgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0xNTA2MTkx
# ODU4MDRaMCMGCSqGSIb3DQEJBDEWBBSJ3ego7exktDgHSqYfdU7EIIib4jANBgkq
# hkiG9w0BAQEFAASCAQBvdcL03nwBTx9C9zC1OlQldpLrFfP2QZXu/Ld0AMBQBToC
# cJyL45XgcDS4sDSz0X0p5ntf80Odlv+3YHV4rUhUwp3s3sYxrQgKeOMarabyQopJ
# HOTn6DyFUn199tCrDj/QPcbQw/3jHmTMbsE4ZNEBYtuvHKenrdGtew/DogD9vAby
# 7zeI7pZGTZillX0/ohMXlWmPjdgx1IER2Iqyu1rxqZEuETO2wA/xzINDnqRJbf27
# ump833SIwyofGXHDPY+akIZleA9gUhO9XZH7dKW+C9D+YlFsYldKKeQ2f3Lw3x0c
# 1c5GJQMujMwBWj7i92zUyu1lmqkgaE+nddCB1fpB
# SIG # End signature block
