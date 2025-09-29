// src/config/navigation.ts
import {
  Home,
  AirVent,
  AlertTriangle,
  Wrench,
  Shield,
  type LucideIcon,
} from "lucide-react";

type NavigationItem = {
  title: string;
  href: string;
  icon: LucideIcon;
  description?: string;
};

export const navigation: NavigationItem[] = [
  {
    title: "Home",
    href: "/",
    icon: Home,
  },
  {
    title: "Units",
    href: "/units",
    icon: AirVent,
  },
  {
    title: "Alerts",
    href: "/alerts",
    icon: AlertTriangle,
  },
  {
    title: "Installations",
    href: "/installations",
    icon: Wrench,
  },
  {
    title: "Admin",
    href: "/admin",
    icon: Shield,
  },
];
