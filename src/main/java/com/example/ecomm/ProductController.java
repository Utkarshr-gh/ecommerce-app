package com.example.ecomm;

import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ProductController {

    private static final List<Product> PRODUCTS = List.of(
        new Product(1, "Wireless Headphones", "Noise-cancelling, 30h battery", 2999, "🎧"),
        new Product(2, "Smart Watch", "Heart-rate and sleep tracking", 4499, "⌚"),
        new Product(3, "Backpack", "Water-resistant, 25L", 1799, "🎒"),
        new Product(4, "Sneakers", "Lightweight everyday runners", 3299, "👟"),
        new Product(5, "Coffee Mug", "Insulated steel, 350ml", 599, "☕"),
        new Product(6, "Desk Lamp", "LED, adjustable brightness", 1299, "💡")
    );

    @GetMapping("/api/products")
    public List<Product> products() {
        return PRODUCTS;
    }
}
