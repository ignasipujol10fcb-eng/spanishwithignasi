# Spanish with Ignasi — setup guide

## What's in this repository
- `index.html`: public teaching website with the €0 30-minute trial, €15 50-minute lesson, and Udemy self-paced course.
- `portal.html`: student/teacher portal UI with sign-in, booking requests, calendar, teacher drag-to-reschedule, private messaging UI and learning links.
- `config.js`: public Supabase project URL, anon key, and teacher user UUID placeholders.
- `supabase/schema.sql`: database tables and initial Row Level Security policies.

## Important status
The public site and portal frontend are committed, but the portal will not accept real bookings or messages until Supabase is configured. A website alone cannot safely provide authentication, private messages, or durable bookings. No payment credentials are included. Payment processing is not integrated; the payment area explains that instructions will be provided after a booking is confirmed.

## Activate the portal
1. Create a Supabase project at https://supabase.com/ (free tier may be sufficient to start).
2. In Supabase → SQL Editor, run the complete `supabase/schema.sql` file.
3. In Supabase → Authentication → URL Configuration, set the site URL to your published GitHub Pages URL and add that URL to the redirect allow list.
4. In Authentication settings, enable email/password sign-in. Configure email confirmation according to your preference.
5. Create a teacher account through `portal.html` first. Confirm the email if required.
6. In Supabase → Table Editor → profiles, find that account and set `role` to `teacher` (or run the SQL update at the bottom of schema.sql, replacing the placeholder email with your sign-in email). Never let a public client set its own role.
7. Copy the Project URL and publishable/anon key from Supabase → Project Settings → API. Put them into `config.js` as `supabaseUrl` and `supabaseAnonKey`. Set `teacherUserId` to the teacher account UUID from Authentication → Users.
8. Commit the edited `config.js` to GitHub. The URL and anon key are intended for browser use; NEVER put the service-role key in this file.
9. In GitHub → repository Settings → Pages, publish from branch `main`, folder `/(root)`. Wait for the deployment and open `portal.html`.

## Teacher calendar and rescheduling
The portal uses FullCalendar. When signed in as the teacher, existing lesson events can be dragged to another time. Database access policies ensure only a teacher can update lesson rows. After a move, send the student a message with the new time. Conflict checks and automatic email notifications are not yet implemented; add server-side booking validation before accepting public bookings at scale.

## Booking rules
- Free trial: 30 minutes, €0.
- Standard private lesson: 50 minutes, €15.
- Student bookings are requests, not confirmed until the teacher approves them.
- Do not store IBAN, PayPal, Payoneer or Revolut secrets in the source code. Payment links/details can be configured later. This version does not collect payment or verify transfers.

## Security checklist before launch
- Review the SQL policies in your own Supabase project.
- Confirm the teacher role manually from the dashboard; do not expose service-role credentials.
- Add server-side overlap checks so two bookings cannot claim the same time.
- Configure email notifications and reschedule request approval.
- Add privacy policy, terms, cancellation/refund rules and applicable tax/business disclosures.
- Test with a separate student account to confirm students cannot access another student's lessons or messages.

## Local preview
Open `index.html` for the public website. For portal authentication, configure Supabase first. GitHub Pages serves static files only; Supabase provides the secure backend.
