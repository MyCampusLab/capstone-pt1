export interface FallbackTenant {
  id: number;
  slug: string;
  name: string;
  address: string;
  phone: string;
  chairs_count: number;
}

export interface FallbackBarber {
  id: number;
  tenant_id: number;
  name: string;
  chair_number: number;
  speed_factor: number;
  speed_val: number;
}

export interface FallbackService {
  id: number;
  tenant_id: number;
  name: string;
  price: number;
  complexity_score: number;
  base_duration_min: number;
  category: 'ringan' | 'sedang' | 'tinggi';
}

export const FALLBACK_TENANTS: FallbackTenant[] = [
  {
    id: 1,
    slug: 'febrian-barbershop',
    name: 'Febrian Barbershop',
    address: 'Mejasem Barat, Kec. Kramat, Kab. Tegal',
    phone: '081234567890',
    chairs_count: 4,
  },
  {
    id: 2,
    slug: 'rr-barber-studio',
    name: 'RR Barber Studio',
    address: 'Tegal, Jawa Tengah',
    phone: '081234567891',
    chairs_count: 3,
  },
  {
    id: 3,
    slug: 'stupid-culture',
    name: 'Stupid Culture Barbershop',
    address: 'Jl. Kapten Ismail No. 20, Kota Tegal',
    phone: '085727566125',
    chairs_count: 3,
  },
];

export const FALLBACK_BARBERS: FallbackBarber[] = [
  { id: 1, tenant_id: 1, name: 'Ferdi', chair_number: 1, speed_factor: 0.85, speed_val: 20.0 },
  { id: 2, tenant_id: 1, name: 'Febri', chair_number: 2, speed_factor: 1.00, speed_val: 30.0 },
  { id: 3, tenant_id: 1, name: 'Hakim', chair_number: 3, speed_factor: 1.20, speed_val: 40.0 },
  { id: 4, tenant_id: 2, name: 'Kapster 1', chair_number: 1, speed_factor: 1.00, speed_val: 25.0 },
  { id: 5, tenant_id: 2, name: 'Kapster 2', chair_number: 2, speed_factor: 1.20, speed_val: 35.0 },
  { id: 6, tenant_id: 3, name: 'Bagas', chair_number: 1, speed_factor: 0.85, speed_val: 20.0 },
  { id: 7, tenant_id: 3, name: 'Reno', chair_number: 2, speed_factor: 1.00, speed_val: 30.0 },
  { id: 8, tenant_id: 3, name: 'Danang', chair_number: 3, speed_factor: 1.20, speed_val: 35.0 },
];

export const FALLBACK_SERVICES: FallbackService[] = [
  { id: 1, tenant_id: 1, name: 'Potong Rambut Standar', price: 40000, complexity_score: 2.5, base_duration_min: 25, category: 'ringan' },
  { id: 2, tenant_id: 1, name: 'Skin Fade & Beard Sculpting', price: 45000, complexity_score: 5.5, base_duration_min: 35, category: 'sedang' },
  { id: 3, tenant_id: 1, name: 'Pewarnaan / Hair Color', price: 80000, complexity_score: 8.5, base_duration_min: 60, category: 'tinggi' },
  { id: 4, tenant_id: 2, name: 'Signature Haircut', price: 35000, complexity_score: 2.5, base_duration_min: 30, category: 'ringan' },
  { id: 5, tenant_id: 2, name: 'Fade Haircut', price: 40000, complexity_score: 5.5, base_duration_min: 35, category: 'sedang' },
  { id: 6, tenant_id: 2, name: 'Coloring / Bleaching', price: 75000, complexity_score: 8.5, base_duration_min: 60, category: 'tinggi' },
  { id: 7, tenant_id: 3, name: 'Gentleman Haircut (AC)', price: 25000, complexity_score: 2.5, base_duration_min: 25, category: 'ringan' },
  { id: 8, tenant_id: 3, name: 'Taper / Skin Fade', price: 35000, complexity_score: 5.5, base_duration_min: 35, category: 'sedang' },
  { id: 9, tenant_id: 3, name: 'Hair Coloring / Cat', price: 65000, complexity_score: 8.5, base_duration_min: 60, category: 'tinggi' },
];
