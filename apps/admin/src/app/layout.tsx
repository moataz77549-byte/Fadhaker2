import React from "react";

export const metadata = {
  title: "لوحة تحكم فذكر",
  description: "لوحة الإدارة المركزية لمنصة وتطبيق فذكر",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="ar" dir="rtl">
      <head>
        <meta charSet="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          href="https://fonts.googleapis.com/css2?family=Noto+Sans+Arabic:wght@400;500;600;700&display=swap"
          rel="stylesheet"
        />
        <style>{`
          :root {
            --color-primary: #243B6B;
            --color-primary-dark: #162746;
            --color-teal: #2E9E9E;
            --color-copper: #C77955;
            --color-pearl: #F8F6F1;
            --color-night: #0E1726;
            --color-light-surface: #FFFFFF;
            --color-dark-surface: #172235;
          }
          * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
          }
          body {
            font-family: 'Noto Sans Arabic', system-ui, -apple-system, sans-serif;
            background-color: var(--color-pearl);
            color: #1A202C;
            min-height: 100vh;
            direction: rtl;
          }
        `}</style>
      </head>
      <body>{children}</body>
    </html>
  );
}
