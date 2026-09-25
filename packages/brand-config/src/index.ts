import tokens from './tokens.json';

export interface FadhkurBrand {
  name: {
    ar: string;
    en: string;
    code: string;
  };
  tagline: {
    ar: string;
    en: string;
  };
  identifiers: {
    defaultPackageId: string;
    androidAppId: string;
    iosBundleId: string;
    warning: string;
  };
  links: {
    supportEmail: string;
    privacyPolicy: string;
    termsOfService: string;
    githubRepo: string;
  };
}

export interface FadhkurColorTokens {
  primary: string;
  primaryDark: string;
  teal: string;
  copper: string;
  pearl: string;
  night: string;
  lightSurface: string;
  darkSurface: string;
  lightSurfaceVariant: string;
  darkSurfaceVariant: string;
  lightTextPrimary: string;
  lightTextSecondary: string;
  darkTextPrimary: string;
  darkTextSecondary: string;
  accentGold: string;
  statusOnline: string;
  statusError: string;
  statusWarning: string;
}

export interface FadhkurTypographyTokens {
  arabicUI: string;
  quranText: string;
  latin: string;
  mono: string;
}

export const BRAND: FadhkurBrand = tokens.brand;
export const COLORS: FadhkurColorTokens = tokens.colors;
export const TYPOGRAPHY: FadhkurTypographyTokens = tokens.typography;
export const RADII = tokens.radii;

export default tokens;
