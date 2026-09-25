import Link from "next/link";
import { BrandMark } from "@/components/BrandMark";

export default function Home() {
  return (
    <main style={{
      display: "flex",
      minHeight: "100vh",
      alignItems: "center",
      justifyContent: "center",
      padding: "2rem",
      backgroundColor: "#0E1726",
      color: "#F8F6F1"
    }}>
      <div style={{
        maxWidth: "480px",
        width: "100%",
        textAlign: "center",
        backgroundColor: "#172235",
        padding: "3rem 2rem",
        borderRadius: "16px",
        boxShadow: "0 10px 25px rgba(0,0,0,0.3)"
      }}>
        <div style={{ display: "flex", justifyContent: "center", marginBottom: "1.5rem" }}>
          <BrandMark size={72} />
        </div>
        <h1 style={{ fontSize: "1.8rem", fontWeight: "bold", marginBottom: "0.5rem" }}>
          فذكر
        </h1>
        <p style={{ color: "#2E9E9E", marginBottom: "2rem", fontSize: "0.95rem" }}>
          لوحة الإدارة وإدارة الإذاعات والتلاوات
        </p>
        <Link
          href="/dashboard"
          style={{
            display: "inline-block",
            width: "100%",
            padding: "0.85rem",
            backgroundColor: "#243B6B",
            color: "#FFFFFF",
            borderRadius: "8px",
            textDecoration: "none",
            fontWeight: "600",
            marginBottom: "1rem",
            boxShadow: "0 4px 12px rgba(36,59,107,0.4)"
          }}
        >
          الدخول إلى لوحة التحكم
        </Link>
        <Link
          href="/login"
          style={{
            display: "inline-block",
            color: "#C77955",
            fontSize: "0.9rem",
            textDecoration: "none"
          }}
        >
          تسجيل الدخول الإداري
        </Link>
      </div>
    </main>
  );
}
