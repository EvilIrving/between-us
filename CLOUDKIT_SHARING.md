# CloudKit sharing — verbatim excerpts

Retrieved 2026-09-21.

## Shared Records

https://developer.apple.com/documentation/cloudkit/shared-records

> "You store shareable records in a custom record zone in the user's private database."

> "CloudKit then creates a record zone in the participant's shared database that provides a view into
> the owner's private database. The record zone contains only the records in the share; no other data
> is accessible."

> "A participant with write permissions can change or delete records in this new record zone. Any
> changes they make are visible to all participants."

> "A record can take part in only a single share. This applies to every record in the shared record
> zone or hierarchy."

> "Only invited participants can join a private share. Anyone with the share URL can join a public
> share."

> "To stop sharing, the share's owner must delete the share or, for shared hierarchies, the root
> record. If a participant wants to leave the share, delete the share record from their shared
> database."

> "Use `UICloudSharingController` or `NSSharingService` to allow a participant to stop participating.
> Or remove them from the share using the `removeParticipant(_:)` method, and then save the updated
> share to iCloud."

## CKShare.Participant

https://developer.apple.com/documentation/cloudkit/ckshare/participant

> "If the status is `pending`, use `CKAcceptSharesOperation` to accept the share. Upon acceptance,
> CloudKit makes the shared records available in the participant's shared database. The records remain
> accessible for as long as the participant's status is `accepted`."

> "Anyone with the URL of a public share can become a participant in that share. Participants of a
> public share assume the `publicUser` role. For private shares, the owner manages the participants.
> An owner is any participant with the `owner` role. A participant of a private share can't accept the
> share unless the owner adds them first. Private share participants assume the `privateUser` role."

> "CloudKit removes any pending participants if the owner changes the share's `publicPermission`.
> CloudKit removes all participants if the new permission is `none`."

> "Participants with write permissions can modify or delete any record that you include in the share.
> However, only the owner can delete a shared hierarchy's root record. If a participant attempts to
> delete the share, CloudKit removes the participant. The share remains active for all other
> participants."

## CKShare.publicPermission

https://developer.apple.com/documentation/cloudkit/ckshare/publicpermission

> "Setting this property's value to be more permissive than `CKShare.ParticipantPermission.none`
> allows any user with the share's URL to join. CloudKit removes all public participants when you save
> the share if you set the property's value to `none`."

> "The default value is `CKShare.ParticipantPermission.none`."

## How CloudKit share permissions and participants work — Tact

https://blog.justtact.com/cloudkit-share-permissions/ (2022-09-07)

> "There are two ways for someone to leave a share/chat. Either the owner removes them with the
> `removeParticipant` API, or they leave themselves by deleting the CKShare record. Note that it
> doesn't make sense for the owner to leave a share (or chat in Tact): all shared CloudKit records
> must have an active owner. The only thing that the owner can do to "leave" the chat is to delete the
> whole record (chat)."

> "Even though the owner cannot add new participants, they can still remove participants with the
> `removeParticipant` API as expected."

> "What happens when you change a share's `publicPermission` from `.readWrite` back to `.none`? The
> documentation is pretty clear on this: CloudKit removes all participants if the new permission is
> `none`. Indeed, this is what happens if you do it. All other participants are removed and only the
> owner remains as a participant on the share."

> "A fact that's not obvious from CloudKit documentation: after you change a share's
> `publicPermission` to `readWrite`, the owner can no longer add participants with `addParticipant`
> API. Doing so results in an internal consistency exception. The only way to add participants to a
> public share is if they themselves join the share using the URL."


[text](../../../../../Applications/排版小动物.app)