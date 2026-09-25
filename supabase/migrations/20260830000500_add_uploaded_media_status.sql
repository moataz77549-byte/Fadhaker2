-- UPLOADED means the immutable original exists and passed Storage-level verification,
-- but Audio Worker validation/processing has not started.
alter type app.media_status add value if not exists 'UPLOADED' after 'UPLOADING';
