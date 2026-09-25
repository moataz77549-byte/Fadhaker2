import React from "react";

interface BrandMarkProps {
  size?: number;
  className?: string;
  isRadio?: boolean;
}

export const BrandMark: React.FC<BrandMarkProps> = ({
  size = 40,
  className = "",
  isRadio = false,
}) => {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 108 108"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={className}
      aria-label="شعار فذكر"
    >
      {/* Background Rounded Shield */}
      <rect width="108" height="108" rx="24" fill="#243B6B" />

      {/* Recitation Arc & Acoustic Waves (Teal & Copper) */}
      <path
        d="M36 34C42 28 66 28 72 34"
        stroke="#2E9E9E"
        strokeWidth="3.5"
        strokeLinecap="round"
      />
      <path
        d="M42 41C46 37 62 37 66 41"
        stroke="#C77955"
        strokeWidth="3"
        strokeLinecap="round"
      />

      {/* Acoustic Center Bars */}
      <path
        d="M48 48V44 M54 49V42 M60 48V44"
        stroke="#FFFFFF"
        strokeWidth="3"
        strokeLinecap="round"
      />

      {isRadio && (
        <path
          d="M28 26C38 16 70 16 80 26"
          stroke="#2E9E9E"
          strokeWidth="2.5"
          strokeLinecap="round"
          strokeDasharray="4 4"
        />
      )}

      {/* Left Page of Holy Quran */}
      <path
        d="M52 56C45 52 36 52 30 55C29 55.5 28 56.5 28 57.8V74C28 75 29 75.8 30 75.5C36 73 45 73 52 76.5V56Z"
        fill="#F8F6F1"
      />

      {/* Right Page of Holy Quran */}
      <path
        d="M56 56C63 52 72 52 78 55C79 55.5 80 56.5 80 57.8V74C80 75 79 75.8 78 75.5C72 73 63 73 56 76.5V56Z"
        fill="#FFFFFF"
      />

      {/* Central Binding Spine Accent */}
      <path d="M52 76.5L54 74L56 76.5L54 79L52 76.5Z" fill="#C77955" />

      {/* Wooden Rihal Stand */}
      <path
        d="M34 83L74 83"
        stroke="#C77955"
        strokeWidth="3.5"
        strokeLinecap="round"
      />
      <path
        d="M42 76L66 87 M66 76L42 87"
        stroke="#C77955"
        strokeWidth="3"
        strokeLinecap="round"
      />

      {/* Bookmark Ribbon */}
      <path
        d="M54 57V80L52 83"
        stroke="#2E9E9E"
        strokeWidth="2.5"
        strokeLinecap="round"
      />
    </svg>
  );
};
