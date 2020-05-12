# lync-2013-call-forwarding-information-tool

The purpose of this tool is to give you an easy front end GUI to review your user's call forwarding settings. Information such as who's a delegate of who, who's got simultaneous ring set, who's forwarding where, etc. can be difficult to retrieve without a utility such as sefautil, which itself can be difficult. This tool allows you to review this information for all users in a pool in a GUI format that's easily searchable, sortable, and filterable (Out-Gridview). It also allows you to save the information to a CSV file. The information is gaterhed by parsing data pulled using Export-CSUserData. No SQL calls are made and no data is written back into Lync.

Because this tool uses Export-CSUserData, please be patient during the loading process. If you have difficulty using this utility, first ensure you can run Export-CSUserData successfully. If there is any corrupted user information in a pool, this can cause issues and that corruption will need to be resolved first.

If you would like to see the information in a different format, say an PowerShell command such as Get-CSUserForwardingInfo that can run for a single user or pool for speed, let me know as well. If there's interest I can write it.  Though it runs fine on Skype for Business, a separate Skype for Business utility will be released as well with additional information related to Call Via Work.

Finally, the question that I imagine will be asked is: If you can pull this data as read-only, why not give the ability to modify and write it back and avoid sefautil all together? The quick answer is, I have another utility for this that I have not yet released, and reading the data is much simpler than writing it. I am still putting it through it's paces for quality and will decide if it should be released later.

